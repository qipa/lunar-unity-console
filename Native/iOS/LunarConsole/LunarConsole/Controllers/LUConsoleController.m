//
//  LunarConsoleController.m
//  LunarConsole
//
//  Created by Alex Lementuev on 8/3/15.
//  Copyright (c) 2015 Space Madness. All rights reserved.
//

#import "LUConsoleController.h"

#import "Lunar.h"

static const NSTimeInterval kTableUpdateDelay = 0.1; // 100 ms

@interface LUConsoleController () <LunarConsoleDelegate, LUToggleButtonDelegate, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
{
    LUConsole * _console;
    BOOL        _scrollLocked;
    NSUInteger  _updateScheduled;
    NSUInteger  _lastUpdateOverflowAmount;
}

@property (nonatomic, assign) IBOutlet UITableView * tableView;
@property (nonatomic, assign) IBOutlet UISearchBar * filterBar;

@property (nonatomic, assign) IBOutlet LULogTypeButton * logButton;
@property (nonatomic, assign) IBOutlet LULogTypeButton * warningButton;
@property (nonatomic, assign) IBOutlet LULogTypeButton * errorButton;

@property (nonatomic, assign) IBOutlet NSLayoutConstraint * logTypeButtonTrailingConstraint;

@end

@implementation LUConsoleController

+ (void)load
{
    if (!LU_IOS_MIN_VERSION_AVAILABLE)
    {
        return;
    }
    
    if ([self class] == [LUConsoleController class])
    {
        [LULogTypeButton class]; // force linker to add this class
    }
}

+ (instancetype)controllerWithConsole:(LUConsole *)console
{
    return LU_AUTORELEASE([[[self class] alloc] initWithConsole:console]);
}

- (instancetype)initWithConsole:(LUConsole *)console
{
    self = [super initWithNibName:NSStringFromClass([self class]) bundle:nil];
    if (self)
    {
        _console = LU_RETAIN(console);
    }
    return self;
}

- (void)dealloc
{
    LUAssert(_console.delegate == self);
    _console.delegate       = nil;
    _tableView.delegate     = nil;
    _tableView.dataSource   = nil;
    _filterBar.delegate     = nil;
    _logButton.delegate     = nil;
    _warningButton.delegate = nil;
    _errorButton.delegate   = nil;

    LU_RELEASE(_console);
    LU_SUPER_DEALLOC
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _console.delegate = self;
    _scrollLocked = YES;
    
    LUTheme *theme = [self theme];
    
    // title
    self.title = @"Logs";
    
    // background
    self.view.opaque = YES;
    self.view.backgroundColor = theme.tableColor;
    _tableView.backgroundColor = theme.tableColor;
    
    // log type buttons
    _logButton.delegate = self;
    _warningButton.delegate = self;
    _errorButton.delegate = self;
    
    // overflow control
    _lastUpdateOverflowAmount = _console.overflowAmount;
    
    // log entries count
    [self updateEntriesCount];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    // TODO: clean up cells
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark -
#pragma mark Filtering

- (void)filterByText:(NSString *)text
{
    BOOL shouldReload = [_console.entries setFilterByText:text];
    if (shouldReload)
    {
        [self reloadData];
    }
}

- (void)setLogType:(LUConsoleLogType)logType filterDisabled:(BOOL)disabled
{
    BOOL shouldReload = [_console.entries setFilterByLogType:logType disabled:disabled];
    if (shouldReload)
    {
        [self reloadData];
    }
}

#pragma mark -
#pragma mark Actions

- (IBAction)onClose:(id)sender
{
    if ([_delegate respondsToSelector:@selector(consoleControllerDidClose:)])
    {
        [_delegate consoleControllerDidClose:self];
    }
}

- (IBAction)onClear:(id)sender
{
    [_console clear];
}

- (IBAction)onScrollLock:(id)sender
{
    _scrollLocked = !_scrollLocked;
}

- (IBAction)onCopy:(id)sender
{
    NSString *text = [_console getText];
    [self copyTextToClipboard:text];
}

- (IBAction)onEmail:(id)sender
{
    
}

#pragma mark -
#pragma mark LunarConsoleDelegate

- (void)lunarConsole:(LUConsole *)console didAddEntry:(LUConsoleEntry *)entry filtered:(BOOL)filtered
{
    if (!_updateScheduled && filtered)
    {
        _updateScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTableUpdateDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // it's ok to capture self here
            [self updateTable];
            _updateScheduled = NO;
        });
    }
    
    // update entries count
    [self updateEntriesCount];
}

- (void)lunarConsoleDidClearEntries:(LUConsole *)console
{
    [self reloadData];
}

#pragma mark -
#pragma mark LUToggleButtonDelegate

- (void)toggleButtonStateChanged:(LUToggleButton *)button
{
    LUConsoleLogTypeMask mask = 0;
    if (button == _logButton)
    {
        mask |= LU_CONSOLE_LOG_TYPE_MASK(LUConsoleLogTypeLog);
    }
    else if (button == _warningButton)
    {
        mask |= LU_CONSOLE_LOG_TYPE_MASK(LUConsoleLogTypeWarning);
    }
    else if (button == _errorButton)
    {
        mask |= LU_CONSOLE_LOG_TYPE_MASK(LUConsoleLogTypeException) |
                LU_CONSOLE_LOG_TYPE_MASK(LUConsoleLogTypeError) |
                LU_CONSOLE_LOG_TYPE_MASK(LUConsoleLogTypeAssert);
    }
    
    if ([_console.entries setFilterByLogTypeMask:mask disabled:button.isOn])
    {
        [self reloadData];
    }
}

#pragma mark -
#pragma mark Scrolling

- (void)scrollToBottom
{
    NSIndexPath *path = [NSIndexPath indexPathForRow:_console.entriesCount-1 inSection:0];
    [_tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionBottom animated:NO];
}

#pragma mark -
#pragma mark UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _console.entriesCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    LUConsoleEntry *entry = [self entryForRowAtIndexPath:indexPath];
    return [entry tableView:tableView cellAtIndex:indexPath.row];
}

#pragma mark -
#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    LUConsoleEntry *entry = [self entryForRowAtIndexPath:indexPath];
    
    LUConsoleDetailsController *controller = [[LUConsoleDetailsController alloc] initWithEntry:entry];
    [self.navigationController pushViewController:controller animated:YES];
    LU_RELEASE(controller);
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    LUConsoleEntry *entry = [self entryForRowAtIndexPath:indexPath];
    return [entry cellSizeForTableView:tableView].height;
}

- (BOOL)tableView:(UITableView*)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath*)indexPath
{
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    return action == @selector(copy:);
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    LUConsoleEntry *entry = [self entryForRowAtIndexPath:indexPath];
    [self copyTextToClipboard:entry.message];
}

#pragma mark -
#pragma mark UISearchBarDelegate

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:YES animated:YES];
    
    // FIXME: use size classes instead
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
    {
        CGFloat offset = CGRectGetWidth(self.view.bounds) - CGRectGetWidth(self.filterBar.bounds);
        self.logTypeButtonTrailingConstraint.constant = -offset;
        
        [UIView animateWithDuration:0.4 animations:^{
            [self.view layoutIfNeeded];
        }];
    }
    
    return YES;
}

- (BOOL)searchBarShouldEndEditing:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:NO animated:YES];
    
    // FIXME: use size classes instead
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
    {
        self.logTypeButtonTrailingConstraint.constant = 0;
        
        [UIView animateWithDuration:0.4 animations:^{
            [self.view layoutIfNeeded];
        }];
    }
    
    return YES;
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self filterByText:searchText];

    if (searchText.length == 0)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [searchBar resignFirstResponder];
        });
    }
}
         
#pragma mark -
#pragma mark Entries

- (void)updateTable
{
    NSInteger cellsToInsert = _console.entries.totalCount - [_tableView numberOfRowsInSection:0];
    if (cellsToInsert == 0)
    {
        return;
    }
    
    NSUInteger overflowAmount = _console.overflowAmount;
    if (overflowAmount > 0) // console is overfloating: need to remove some top cells
    {
        [_tableView beginUpdates];
        
        cellsToInsert -= _lastUpdateOverflowAmount;
        
        [self removeCellsCount:MIN(overflowAmount, cellsToInsert)];
        [self insertCellsCount:cellsToInsert];
        
        [_tableView endUpdates];
        
        _lastUpdateOverflowAmount = overflowAmount;
    }
    else
    {
        [self insertCellsCount:cellsToInsert];
    }
    
    // scroll to end
    if (_scrollLocked)
    {
        [self scrollToBottom];
    }
}

- (void)removeCellsCount:(NSInteger)cellsCount
{
    if (cellsCount == 1)
    {
        NSArray *deleteIndices = [[NSArray alloc] initWithObjects:[NSIndexPath indexPathForRow:0 inSection:0], nil];
        [_tableView deleteRowsAtIndexPaths:deleteIndices withRowAnimation:UITableViewRowAnimationNone];
        LU_RELEASE(deleteIndices);
    }
    else if (cellsCount > 1)
    {
        NSMutableArray *deleteIndices = [[NSMutableArray alloc] initWithCapacity:cellsCount];
        for (NSInteger rowIndex = 0; rowIndex < cellsCount; ++rowIndex)
        {
            [deleteIndices addObject:[NSIndexPath indexPathForRow:rowIndex inSection:0]];
        }
        [_tableView deleteRowsAtIndexPaths:deleteIndices withRowAnimation:UITableViewRowAnimationNone];
        LU_RELEASE(deleteIndices);
    }
}

- (void)insertCellsCount:(NSInteger)cellsCount
{
    if (cellsCount == 1)
    {
        NSArray *indices = [[NSArray alloc] initWithObjects:[NSIndexPath indexPathForRow:_console.entriesCount - 1 inSection:0], nil];
        [_tableView insertRowsAtIndexPaths:indices withRowAnimation:UITableViewRowAnimationNone];
        LU_RELEASE(indices);
    }
    else if (cellsCount > 1)
    {
        NSMutableArray *indices = [[NSMutableArray alloc] initWithCapacity:cellsCount];
        for (NSInteger i = cellsCount - 1; i >= 0; --i)
        {
            NSInteger rowIndex = _console.entriesCount - i - 1;
            [indices addObject:[NSIndexPath indexPathForRow:rowIndex inSection:0]];
        }
        
        [_tableView insertRowsAtIndexPaths:indices withRowAnimation:UITableViewRowAnimationNone];
        LU_RELEASE(indices);
    }
}

- (void)updateEntriesCount
{
    LUConsoleEntryList *entries = _console.entries;
    _logButton.count = entries.logCount;
    _warningButton.count = entries.warningCount;
    _errorButton.count = entries.errorCount;
}

#pragma mark -
#pragma mark Helpers

- (LUConsoleEntry *)entryForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [_console entryAtIndex:indexPath.row];
}

- (LUConsoleEntry *)entryForRowAtIndex:(NSUInteger)index
{
    return [_console entryAtIndex:index];
}

- (void)reloadData
{
    [_tableView reloadData];
    _lastUpdateOverflowAmount = _console.overflowAmount;
}

- (void)copyTextToClipboard:(NSString *)text
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    [pasteboard setString:text];
}

#pragma mark -
#pragma mark Properties

- (LUTheme *)theme
{
    return [LUTheme mainTheme];
}

@end