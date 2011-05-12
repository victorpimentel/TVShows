/*
 *  This file is part of the TVShows 2 ("Phoenix") source code.
 *  http://github.com/victorpimentel/TVShows/
 *
 *  TVShows is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with TVShows. If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "AppInfoConstants.h"
#import "TabController.h"

#import "SubscriptionsDelegate.h"

#import "TSParseXMLFeeds.h"
#import "TSUserDefaults.h"

#import "TorrentzParser.h"
#import "TheTVDB.h"
#import "LCLLogFile.h"

@implementation TabController

@synthesize selectedShow;

- (void) awakeFromNib
{
    // Set displayed version information
    NSString *bundleVersion = [[[NSBundle bundleWithIdentifier: TVShowsAppDomain] infoDictionary] 
                               valueForKey:@"CFBundleShortVersionString"];
    NSString *buildVersion = [[[NSBundle bundleWithIdentifier: TVShowsAppDomain] infoDictionary]
                              valueForKey:@"CFBundleVersion"];
    NSString *buildDate = [[[NSBundle bundleWithIdentifier: TVShowsAppDomain] infoDictionary]
                           valueForKey:@"TSBundleBuildDate"];
    
    [sidebarHeader setStringValue:@"TVShows 2"];
    [sidebarVersionText setStringValue: [NSString stringWithFormat:@"%@ (r%@)", bundleVersion, buildVersion]];
    [sidebarDateText setStringValue: buildDate];
    
    NSDate *date = [TSUserDefaults getDateFromKey:@"lastCheckedForEpisodes"];
    if (date) {
        // Set the last date/time episodes were checked for.
        NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
        [dateFormatter setDateStyle:NSDateFormatterLongStyle];
        [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
        
        NSDateFormatter *timeFormatter = [[[NSDateFormatter alloc] init] autorelease];
        [timeFormatter setDateStyle:NSDateFormatterNoStyle];
        [timeFormatter setTimeStyle:NSDateFormatterShortStyle];
        
        [lastCheckedDate setStringValue: [[[dateFormatter stringFromDate: date] stringByAppendingString:TSLocalizeString(@" at ")]
                                          stringByAppendingString: [timeFormatter stringFromDate: date]]];
    } else {
        [lastCheckedDate setStringValue: TSLocalizeString(@"Never")];
    }
    
    // Localize everything
    [[prefTabView tabViewItemAtIndex:0] setLabel: TSLocalizeString(@"Subscriptions")];
    [[prefTabView tabViewItemAtIndex:1] setLabel: TSLocalizeString(@"Preferences")];
    [[prefTabView tabViewItemAtIndex:2] setLabel: TSLocalizeString(@"About")];
    
    [feedbackButton setTitle: TSLocalizeString(@"Submit Feedback")];
    
    [addButton setTitle: TSLocalizeString(@"Add Show")];
    [lastCheckedText setStringValue: TSLocalizeString(@"Last Checked:")];
    
    [websiteButton setTitle: TSLocalizeString(@"Website")];
    [donateButton setTitle: TSLocalizeString(@"Donate")];
    [viewLogsButton setTitle: TSLocalizeString(@"View Logs")];
    [uninstallButton setTitle: TSLocalizeString(@"Uninstall")];
    [disclaimer setStringValue: TSLocalizeString(@"No actual videos are downloaded by TVShows, only torrents which will require other programs to use. It is up to you, the user, to decide the legality of using any of the files downloaded by this application, in accordance with applicable copyright laws of you country.")];
    
    [logTitleText setStringValue: TSLocalizeString(@"Recently Logged Activity")];
    [logExplanationText setStringValue: TSLocalizeString(@"A message is logged each time new episodes are checked for. Unless noted otherwise, no new episodes were found.")];
    [logLocalizationText setStringValue: TSLocalizeString(@"Logs are stored in ~/Library/Logs/TVShows/")];
    [closeLogButton setTitle: TSLocalizeString(@"Close")];
    
    // Localize the headings of the table columns
    [[colHD headerCell] setStringValue: TSLocalizeString(@"HD")];
    [[colName headerCell] setStringValue: TSLocalizeString(@"Episode Name")];
    [[colSeason headerCell] setStringValue: TSLocalizeString(@"Season")];
    [[colEpisode headerCell] setStringValue: TSLocalizeString(@"Episode")];
    [[colDate headerCell] setStringValue: TSLocalizeString(@"Published Date")];
    
    // Localize everything else
    [showQuality setTitle: TSLocalizeString(@"Download in HD")];
    [showIsEnabled setTitle: TSLocalizeString(@"Enable downloading new episodes")];
    [statusTitle setStringValue: TSLocalizeString(@"Status")];
    [lastDownloadedTitle setStringValue: TSLocalizeString(@"Last Downloaded")];
    [infoBoxTitle setTitle: TSLocalizeString(@"Info")];
    [prefBoxTitle setTitle: TSLocalizeString(@"Preferences")];
    [closeButton setTitle: TSLocalizeString(@"Close")];
    [unsubscribeButton setTitle: TSLocalizeString(@"Unsubscribe")];
    
    // Sort the subscription list and draw the About box
    [self sortSubscriptionList];
    [self drawAboutBox];
}

- (void) tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    NSRect tabFrame;
    int newWinHeight;
    
    tabFrame = [[tabView window] frame];
    
    // newWinHeight should be equal to the wanted window size (in Interface Builder) + 54 (title bar height)
    if ([[tabViewItem identifier] isEqualTo:@"tabItemPreferences"]) {
        newWinHeight = 560;
    } else if ([[tabViewItem identifier] isEqualTo:@"tabItemSubscriptions"]) {
        newWinHeight = 570;
    }  else if ([[tabViewItem identifier] isEqualTo:@"tabItemAbout"]) {
        newWinHeight = 422;
    } else {
        newWinHeight = 422;
    }
    
    tabFrame = NSMakeRect(tabFrame.origin.x, tabFrame.origin.y - (newWinHeight - (int)(NSHeight(tabFrame))), (int)(NSWidth(tabFrame)), newWinHeight);
    
    [[tabView window] setFrame:tabFrame display:YES animate:YES];
}

- (IBAction) showFeedbackWindow:(id)sender
{
    [JRFeedbackController showFeedback];
}

#pragma mark -
#pragma mark About Tab
- (IBAction) openWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: TVShowsWebsite]];
}

- (IBAction) openTwitter:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: TVShowsTwitter]];
}

- (IBAction) openPaypal:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: TVShowsDonations]];
}

- (IBAction) openUninstaller:(id)sender
{
    // Create an alert box.
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle: TSLocalizeString(@"Yes")];
    [alert addButtonWithTitle: TSLocalizeString(@"No")];
    [alert setMessageText: TSLocalizeString(@"Uninstall TVShows")];
    [alert setInformativeText: TSLocalizeString(@"Are you sure you want to uninstall TVShows? This will also remove all preferences and subscriptions.")];
    [alert setAlertStyle:NSWarningAlertStyle];
    
    // Run the alert and then wait for user input.
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        // Drat! They really do want to uninstall. Find the path to the uninstaller.
        NSString *launchPath = [[NSBundle bundleWithIdentifier: TVShowsAppDomain]
                                pathForResource:@"Uninstaller"
                                ofType:@"app"];
        launchPath = [launchPath stringByAppendingPathComponent:@"Contents/MacOS/applet"];
        
        // Start up an NSTask to run the uninstaller.
        NSTask *uninstaller = [[NSTask alloc] init];
        [uninstaller setLaunchPath:launchPath];
        [uninstaller launch];
        
        [uninstaller release];
    }
    
    [alert release];
}

- (void) drawAboutBox
{
    NSString *pathToAboutBoxText = [[NSBundle bundleWithIdentifier: TVShowsAppDomain] 
                                    pathForResource: @"Credits" 
                                    ofType: @"rtf"];
    
    NSAttributedString *aboutBoxText = [[[NSAttributedString alloc]
                                         initWithPath: pathToAboutBoxText
                                         documentAttributes: nil] autorelease];
    
    [[textView_aboutBox textStorage] setAttributedString:aboutBoxText];
}

#pragma mark -
#pragma mark Log Viewer

- (IBAction) showLogViewerWindow:(id)sender
{
    NSString *loggedItems;
    
    [NSApp beginSheet: logViewerWindow
       modalForWindow: [[NSApplication sharedApplication] mainWindow]
        modalDelegate: nil
       didEndSelector: nil
          contextInfo: nil];
    
    loggedItems = [NSString stringWithContentsOfFile: [LCLLogFile defaultPathInHomeLibraryLogsOrPath:nil]
                                            encoding: NSUTF8StringEncoding
                                               error: NULL];
    
    if (!loggedItems) {
        loggedItems = TSLocalizeString(@"No activity has been logged yet. Have you recently installed TVShows?");
    }
    
    [textView_logViewer setFont:[NSFont fontWithName:@"Monaco" size:10.0]];
    [textView_logViewer setString:loggedItems];
    [textView_logViewer moveToEndOfDocument:nil];
    
    [NSApp runModalForWindow: logViewerWindow];
    [NSApp endSheet: logViewerWindow];
}

- (IBAction) closeLogViewerWindow:(id)sender
{
    [NSApp stopModal];
    [logViewerWindow orderOut: self];
}

#pragma mark -
#pragma mark Subscriptions Tab
- (IBAction) displayShowInfoWindow:(id)sender
{
    selectedShow = [[[sender cell] representedObject] representedObject];
    
    // Set up the date formatter
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    [dateFormatter setDateStyle:NSDateFormatterLongStyle];
    [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
    
    // Set the available values now
    [showName setStringValue: [selectedShow valueForKey:@"name"]];
    [showStatus setStringValue: TSLocalizeString(@"Unknown")];
    [showLastDownloaded setStringValue: [dateFormatter stringFromDate:[selectedShow valueForKey:@"lastDownloaded"]]];
    [showQuality setState: [[selectedShow valueForKey:@"quality"] intValue]];
    [showIsEnabled setState: [[selectedShow valueForKey:@"isEnabled"] boolValue]];
    
    NSImage *defaultPoster = [[[NSImage alloc] initByReferencingFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"posterArtPlaceholder" ofType:@"jpg"]] autorelease];
    [defaultPoster setSize: NSMakeSize(127, 184)];
    [showPoster setImage: defaultPoster];
    
    // Reset the Episode Array Controller
    [[episodeArrayController content] removeAllObjects];
    [episodeTableView reloadData];
    
    NSString *selectedShowName = [selectedShow valueForKey:@"name"];
    
    // Display the show poster now that it's been resized.
    [self performSelectorInBackground:@selector(setPosterForShow:) withObject:selectedShowName];
    
    // Grab the show status
    [self performSelectorInBackground:@selector(setStatusForShow:) withObject:selectedShowName];
    
    // Grab the list of episodes
    [self performSelector:@selector(setEpisodesForShow)];
    
    [NSApp beginSheet: showInfoWindow
       modalForWindow: [[NSApplication sharedApplication] mainWindow]
        modalDelegate: nil
       didEndSelector: nil
          contextInfo: nil];
    
    [NSApp runModalForWindow: showInfoWindow];
    [NSApp endSheet: showInfoWindow];
}

- (void) setEpisodesForShow
{
    NSArray *results = [TSParseXMLFeeds parseEpisodesFromFeed:[selectedShow valueForKey:@"url"] maxItems:10];
    
    if ([results count] == 0) {
        LogError(@"Could not download/parse feed for %@ <%@>", [selectedShow valueForKey:@"name"], [selectedShow valueForKey:@"url"]);
    } else {
        [episodeArrayController addObjects:results];
        
        // Check if there are HD episodes, if so enable the "Download in HD" checkbox
        BOOL feedHasHDEpisodes = [TSParseXMLFeeds feedHasHDEpisodes:results];
        
        if (!feedHasHDEpisodes) {
            [showQuality setState:NO];
        }
        [showQuality setEnabled:feedHasHDEpisodes];
        
        // Update the filter predicate to only display the correct quality.
        [self showQualityDidChange:nil];
    }
}

- (void) setStatusForShow:(NSString *)show
{
    NSString *status = [TheTVDB getShowStatus:show];
    NSString *copy = [selectedShow valueForKey:@"name"];

    // Check if the request is still valid (an impacient user may start to rapidly change)
    if ([show isEqualToString:copy]) {
        [showStatus setStringValue: TSLocalizeString(status)];
    }
}

- (void) setPosterForShow:(NSString *)show
{
    NSImage *poster = [[[TheTVDB getPosterForShow:show withHeight:184 withWidth:127] copy] autorelease];
    NSString *copy = [selectedShow valueForKey:@"name"];
    
    // Check if the request is still valid (an impacient user may start to rapidly change)
    if ([show isEqualToString:copy]) {
        [showPoster setImage: poster];
        [showPoster display];
    }
}

- (IBAction) closeShowInfoWindow:(id)sender
{
    // NSManagedContext objectWithID is required for it to save changes to the disk.
    // We also need to update the original selectedShow NSManagedObject so that the
    // interface displays any changes when the window is opened multiple times a session.
    id delegateClass = [[[SubscriptionsDelegate class] alloc] init];
    NSManagedObject *selectedShowObj = [[delegateClass managedObjectContext] objectWithID:[selectedShow objectID]];
    
    // Update the per-show preferences
    [selectedShow setValue:[NSNumber numberWithInt:[showQuality state]] forKey:@"quality"];
    [selectedShow setValue:[NSNumber numberWithBool:[showIsEnabled state]] forKey:@"isEnabled"];
    [selectedShowObj setValue:[NSNumber numberWithInt:[showQuality state]] forKey:@"quality"];
    [selectedShowObj setValue:[NSNumber numberWithBool:[showIsEnabled state]] forKey:@"isEnabled"];
    
    // Be sure to process pending changes before saving or it won't save correctly.
    [[delegateClass managedObjectContext] processPendingChanges];
    [delegateClass saveAction];
    [delegateClass release];
    
    // Reset the selected show and close the window
    selectedShow = nil;
    [NSApp stopModal];
    [showInfoWindow orderOut: self];
}

- (IBAction) showQualityDidChange:(id)sender
{
    if ([showQuality state]) {
        // Is HD and HD is enabled.
        [episodeArrayController setFilterPredicate:[NSPredicate predicateWithFormat:@"isHD == '1'"]];
    } else {
        // Is not HD and HD is not enabled.
        [episodeArrayController setFilterPredicate:[NSPredicate predicateWithFormat:@"isHD == '0'"]];
    }
}

- (void) startDownloadingURL:(NSString *)url withFileName:(NSString *)fileName
{
    // Process the URL if the is not found
    if ([url rangeOfString:@"http"].location == NSNotFound) {
        LogInfo(@"Retrieving an HD torrent file from Torrentz of: %@", url);
        url = [TorrentzParser getAlternateTorrentForEpisode:url];
        if (url == nil) {
            LogError(@"Unable to found an HD torrent file for: %@",fileName);
            return;
        }
    }
    
    // Method copied from TVShowsHelper.m
    LogInfo(@"Attempting to download episode: %@", fileName);
    NSData *fileContents = [NSData dataWithContentsOfURL: [NSURL URLWithString:url]];
    NSString *saveLocation = [[TSUserDefaults getStringFromKey:@"downloadFolder"] stringByAppendingPathComponent:fileName];
    
    [fileContents writeToFile:saveLocation atomically:YES];
    
    if (!fileContents || [fileContents length] < 100) {
        LogError(@"Unable to download file: %@ <%@>",fileName, url);
    } else {
        // The file downloaded successfully, continuing...
        LogInfo(@"Episode downloaded successfully.");
        
        // Check to see if the user wants to automatically open new downloads
        if([TSUserDefaults getBoolFromKey:@"AutoOpenDownloadedFiles" withDefault:1]) {
            [[NSWorkspace sharedWorkspace] openFile:saveLocation withApplication:nil andDeactivate:NO];
        }
    }
}

- (NSObject *) getEpisodeAtRow:(NSInteger)row
{
    for (NSObject *episode in [episodeArrayController content]) {
        if ([[episode valueForKey:@"isHD"] boolValue] == [showQuality state]) {
            if (row == 0) {
                return episode;
            } else {
                row--;
            }
        }
    }
    return nil;
}

- (BOOL) tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
    // Check to see whether or not this is the GET button or not.
    // If it's not, then return YES for shouldSelectRow.
    BOOL result = YES;
    
    // Which column and row was clicked?
    NSInteger clickedCol = [episodeTableView clickedColumn];
    NSInteger clickedRow = [episodeTableView clickedRow];
    
	// Should the episode be downloaded in its own folder?
	
	BOOL sortInFolders = [TSUserDefaults getBoolFromKey:@"sortInFolders" withDefault:YES];
	
    if (clickedRow >= 0 && clickedCol >= 0) {
        // Grab information about the clicked cell.
        NSCell *cell = [episodeTableView preparedCellAtColumn:clickedCol row:clickedRow];
        
        // If the cell is an NSButtonCell and it's enabled...
        if ([cell isKindOfClass:[NSButtonCell class]] && [cell isEnabled]) {
            // Don't select the row
            result = NO;
            
            // This currently only returns a Torrent file and should eventually regex
            // out the actual file extension of the item we're downloading.
            NSObject *episode = [self getEpisodeAtRow:clickedRow];
			
			NSMutableString* fileName = [NSMutableString string];
			if (sortInFolders) {
				[[NSFileManager defaultManager]
				 createDirectoryAtPath:[[TSUserDefaults getStringFromKey:@"downloadFolder"] stringByAppendingFormat:@"/%@", [selectedShow valueForKey:@"name"]]
				 withIntermediateDirectories:NO attributes:nil error:nil];
				[fileName appendFormat:@"%@/", [selectedShow valueForKey:@"name"]];
			}
			[fileName appendFormat:@"%@.torrent", [episode valueForKey:@"episodeName"]];

            [self startDownloadingURL:[episode valueForKey:@"link"]
                         withFileName:fileName];
        }
    }
    
    return result;
}

- (void) sortSubscriptionList
{
    // Arguably, I don't really know how this works, and I only reached this method
    // after hours and hours of debugging and trying to make the NSArrayController not
    // send all its elements to the NSControllerView in every sorting step.
    // But OMG, THIS IS THE MOST AMAZING THING IN THE WORLD
    // IT'S SO GOOD I WANT TO HAVE KIDS WITH IT,
    // KILL THEM AND THEN MAKE MORE KIDS
    [SBArrayController setUsesLazyFetching:YES];
    
    NSSortDescriptor *SBSortDescriptor = [[NSSortDescriptor alloc] initWithKey: @"sortName"
                                                                     ascending: YES
                                                                      selector: @selector(caseInsensitiveCompare:)];
    [SBArrayController setSortDescriptors:[NSArray arrayWithObject:SBSortDescriptor]];
    
    [SBSortDescriptor release];
}

- (IBAction) unsubscribeFromShow:(id)sender
{
    id delegateClass = [[[SubscriptionsDelegate class] alloc] init];
    NSManagedObject *selectedShowObj = [[delegateClass managedObjectContext] objectWithID:[selectedShow objectID]];
    
    // I don't understand why I have to remove the object from both locations
    // but it works so I won't question it.
    [SBArrayController removeObject:selectedShow];
    [[delegateClass managedObjectContext] deleteObject:selectedShowObj];
    
    [self closeShowInfoWindow:(id)sender];
    
    [delegateClass saveAction];
    [delegateClass release];
}

- (void) dealloc
{
    [selectedShow release];
    [super dealloc];
}

@end
