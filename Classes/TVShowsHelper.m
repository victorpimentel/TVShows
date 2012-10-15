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
#import "TVShowsHelper.h"
#import "PreferencesController.h"
#import "PresetTorrentsController.h"
#import "TorrentzParser.h"
#import "TSParseXMLFeeds.h"
#import "TSUserDefaults.h"
#import "SUUpdaterSubclass.h"
#import "RegexKitLite.h"
#import "TSRegexFun.h"
#import "TheTVDB.h"
#import "TSTorrentFunctions.h"

@implementation TVShowsHelper

@synthesize checkerLoop, TVShowsHelperIcon, subscriptionsDelegate, presetShowsDelegate;

- init
{
    if((self = [super init])) {
        checkerThread = nil;
        checkerLoop = nil;
        manually = NO;
        
        NSMutableString *appPath = [NSMutableString stringWithString:[[NSBundle bundleForClass:[self class]] bundlePath] ];
        [appPath replaceOccurrencesOfString:@"TVShowsHelper.app"
                                 withString:@""
                                    options:0
                                      range:NSMakeRange(0, [appPath length])];
        
        TVShowsHelperIcon = [[NSData alloc] initWithContentsOfFile:
                             [appPath stringByAppendingPathComponent:@"TVShows-On-Large.icns"]];
        
        misoBackend = [[Miso alloc] init];
        
        [misoBackend setDelegate:self];
        
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                            selector:@selector(authenticatedOnMiso:)
                                                                name:@"TSMisoAuthenticated"
                                                              object:nil];
        
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(awakeFromSleep)
                                                                   name:NSWorkspaceDidWakeNotification
                                                                 object:nil];
    }
    
    return self;
}

- (void) awakeFromNib
{
    // This should never happen, but let's make sure TVShows is enabled before continuing.
    if ([TSUserDefaults getBoolFromKey:@"isEnabled" withDefault:YES]) {
        
        // Set up Growl notifications
        [GrowlApplicationBridge setGrowlDelegate:self];
        
        // Show the menu if the user wants
        if([TSUserDefaults getBoolFromKey:@"ShowMenuBarIcon" withDefault:YES]) {
            [self activateStatusMenu];
        }
        
        // Check first if we have to add or delete subscriptions because of Miso
        if ([TSUserDefaults getBoolFromKey:@"MisoEnabled" withDefault:NO]) {
            // Try to login in Miso
            manually = NO;
            [misoBackend authorizeWithKey:MISO_API_KEY secret:MISO_API_SECRET];
        } else {
            [self checkNow:nil];
        }
        
    } else {
        // TVShows is not enabled.
        LogWarning(@"The TVShowsHelper was running even though TVShows is not enabled. Quitting.");
        [self quitHelper:nil];
    }
}

- (NSObject *)getShow:(NSString *)showId fromArray:(NSArray *)array
{
    for (NSObject *show in array) {
        if ([[[show valueForKey:@"tvdbID"] description] isEqualToString:showId]) {
            return show;
        }
    }
    
    return nil;
}

- (NSObject *)getShow:(NSString *)showId withName:(NSString *)seriesName fromDictionary:(NSDictionary *)dict
{
    for (NSObject *show in dict) {
        if ([[[[show valueForKey:@"media"] valueForKey:@"tvdb_id"] description] isEqualToString:showId] ||
            [[[[show valueForKey:@"media"] valueForKey:@"title"] description] isEqualToString:seriesName]) {
            return show;
        }
    }
    
    return nil;
}

- (void)followSubscriptions:(NSDictionary *)followedShows
{
    // Fetch subscriptions
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Subscription"
                                              inManagedObjectContext:[subscriptionsDelegate managedObjectContext]];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    
    NSError *error = nil;
    NSArray *subscriptions = [[subscriptionsDelegate managedObjectContext] executeFetchRequest:request error:&error];
    
    // Follow on Miso our (this is made only when the user manually enter the credentials)
    for (NSDictionary *show in subscriptions) {
        // Get the TVDB id
        NSString *showID = [[show valueForKey:@"tvdbID"] description];
        
        // Disregard custom RSS and check if the show is been already followed
        if (showID && ![show valueForKey:@"filters"] &&
            ![self getShow:showID withName:[show valueForKey:@"name"] fromDictionary:followedShows]) {
            
            // Search for it on Miso
            NSDictionary *results = [misoBackend showWithQuery:[show valueForKey:@"name"]];
            
            // Filter those results by TVDB id
            NSObject *newShow = [self getShow:[[show valueForKey:@"tvdbID"] description]
                                     withName:[show valueForKey:@"name"] fromDictionary:results];
            
            // Some shows do not have TVDB ids yet; try to map them together
            if (!newShow) {
                // Just pick the first show (too late, I cannot even think anymore)
                for (NSObject *result in results) {
                    newShow = result;
                    break;
                }
                // If the name is not equal... go back
                if (newShow && ![[[newShow valueForKey:@"media"] valueForKey:@"title"] isEqualToString:[show valueForKey:@"name"]]) {
                    newShow = nil;
                }
            }
            
            // At this point, it should be a valid show, but maybe it is not on the Miso database yet
            if (newShow && ![[[newShow valueForKey:@"media"] valueForKey:@"currently_favorited"] boolValue]) {
                LogInfo(@"Adding show %@ on Miso.", [show valueForKey:@"name"]);
                
                [misoBackend favoriteShow:[[[newShow valueForKey:@"media"] valueForKey:@"id"] description]];
            }
        }
    }
}

- (void)unsubscribeFromUnfollowedShows:(NSDictionary *)followedShows
{
    // Fetch subscriptions
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Subscription"
                                              inManagedObjectContext:[subscriptionsDelegate managedObjectContext]];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    
    NSError *error = nil;
    NSArray *subscriptions = [[subscriptionsDelegate managedObjectContext] executeFetchRequest:request error:&error];
    
    // Delete from our subscriptions unfollowed shows on Miso
    for (NSManagedObject *show in subscriptions) {
        // Get the TVDB id
        NSString *showID = [[show valueForKey:@"tvdbID"] description];
        NSString *seriesName = [show valueForKey:@"name"];
        
        // Check if the show is been followed and if it is a custom RSS (if it has some filters)
        if (![show valueForKey:@"filters"] &&
            ![self getShow:showID withName:seriesName fromDictionary:followedShows] &&
            followedShows != nil && [followedShows count] > 0) {
            
            // Some shows do not have TVDB ids yet; search for it on Miso to see if they are favorited
            NSDictionary *results = [misoBackend showWithQuery:seriesName];
            
            // Let's see if the show has id
            if (![self getShow:showID withName:(NSString *)seriesName fromDictionary:results]) {
                
                NSObject *newShow = nil;
                
                // Just pick the first show (too late, I cannot even think anymore)
                for (NSObject *result in results) {
                    newShow = result;
                    break;
                }
                
                // If the name is not equal... do not remove
                if (newShow && ![[[newShow valueForKey:@"media"] valueForKey:@"title"] isEqualToString:seriesName]) {
                    continue;
                }
                
                // Or if this show is favorited... do it
                if (newShow && [[[newShow valueForKey:@"media"] valueForKey:@"currently_favorited"] boolValue]) {
                    continue;
                }
            }
            
            LogInfo(@"Unsubscribe show %@ because of Miso.", seriesName);
            NSManagedObject *selectedShow = [[subscriptionsDelegate managedObjectContext] objectWithID:[show objectID]];
            
            [[subscriptionsDelegate managedObjectContext] deleteObject:selectedShow];
            
            [[subscriptionsDelegate managedObjectContext] processPendingChanges];
            [subscriptionsDelegate saveAction];
            
            changed = YES;
        }
    }
}

- (void)subscribeToFollowedShows:(NSDictionary *)followedShows
{
    // Fetch subscriptions
    NSEntityDescription *entitySubscriptions = [NSEntityDescription entityForName:@"Subscription"
                                                           inManagedObjectContext:[subscriptionsDelegate managedObjectContext]];
    NSFetchRequest *requestSubscriptions = [[[NSFetchRequest alloc] init] autorelease];
    [requestSubscriptions setEntity:entitySubscriptions];
    
    NSError *error = nil;
    NSArray *subscriptions = [[subscriptionsDelegate managedObjectContext]
                              executeFetchRequest:requestSubscriptions error:&error];
    
    // Fetch presets
    NSEntityDescription *entityPresets = [NSEntityDescription entityForName:@"Show"
                                                     inManagedObjectContext:[presetShowsDelegate managedObjectContext]];
    NSFetchRequest *requestPresets = [[[NSFetchRequest alloc] init] autorelease];
    [requestPresets setEntity:entityPresets];
    
    NSArray *presets = [[presetShowsDelegate managedObjectContext]
                        executeFetchRequest:requestPresets error:&error];
    
    // The other way around, update our subscriptions with the followed shows on Miso
    for (NSDictionary *show in followedShows) {
        // Get the precious data for that show
        NSString *showID = [[[show valueForKey:@"media"] valueForKey:@"tvdb_id"] description];
        NSString *seriesName = [[show valueForKey:@"media"] valueForKey:@"title"];
        
        // Let's check that the show is in the preset show list
        NSObject *selectedShow = [self getShow:showID fromArray:presets];
        // Some shows do not have TVDB ids yet; try to map them together
        if (!selectedShow && (!showID || [showID isEqualToString:@"<null>"] || [showID length] == 0)) {
            // Just pick the first show with that name, if there is any
            for (NSObject *presetShow in presets) {
                if ([[presetShow valueForKey:@"displayName"] isEqualToString:seriesName]) {
                    selectedShow = presetShow;
                    showID = [[presetShow valueForKey:@"tvdbID"] description];
                    break;
                }
            }
        }
        
        // If the user is not subscribed to this show and the show is still airing, add to the subscriptions
        if (selectedShow && ![self getShow:showID fromArray:subscriptions] &&
            ![[TheTVDB getShowStatus:seriesName withShowID:showID] isEqualToString:@"Ended"]) {
            
            LogInfo(@"Adding show %@ from Miso.", seriesName);
            
            NSManagedObject *newSubscription = [NSEntityDescription insertNewObjectForEntityForName:@"Subscription"
                                                                             inManagedObjectContext:[subscriptionsDelegate managedObjectContext]];
            
            // Set the information about the new show
            [newSubscription setValue:[selectedShow valueForKey:@"displayName"] forKey:@"name"];
            [newSubscription setValue:[selectedShow valueForKey:@"sortName"] forKey:@"sortName"];
            [newSubscription setValue:[selectedShow valueForKey:@"tvdbID"] forKey:@"tvdbID"];
            [newSubscription setValue:[selectedShow valueForKey:@"name"] forKey:@"url"];
            [newSubscription setValue:[NSNumber numberWithBool:[TSUserDefaults getBoolFromKey:@"AutoSelectHDVersion" withDefault:NO]]
                               forKey:@"quality"];
            [newSubscription setValue:[NSNumber numberWithBool:YES] forKey:@"isEnabled"];
            
            // OK, so we know that the user has Miso.
            // And that the user has followed a "new" show.
            // So let's go back in time thirteen days so that the last episodes
            // will be downloaded. So that user can leverage this Miso synchronization.
            // If the user does not want to download an episode he can cancel,
            // but the other user case is more cumbersome.
            // Anyway, if the user did a check-in for th(at/ose) episode(s)
            // it will not be downloaded (and again, the user is Miso synced)
            [newSubscription setValue:[NSDate dateWithTimeIntervalSinceNow:-6*24*60*60] forKey:@"lastDownloaded"];
            
            [[subscriptionsDelegate managedObjectContext] processPendingChanges];
            [subscriptionsDelegate saveAction];
            
            changed = YES;
        }
    }
}

- (void)syncShows
{
    // Check the followed shows and process them
    NSDictionary *followedShows = [misoBackend favoritedShows];
    
    if (followedShows) {
        changed = NO;
        if ([TSUserDefaults getBoolFromKey:@"MisoSyncInProgress" withDefault:NO]) {
            [self followSubscriptions:followedShows];
            [TSUserDefaults setKey:@"MisoSyncInProgress" fromBool:NO];
        } else {
            [self unsubscribeFromUnfollowedShows:followedShows];
        }
        [self subscribeToFollowedShows:followedShows];
        // Warn the pref pane
        if (changed) {
            [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"TSUpdatedShows" object:nil];
            changed = NO;
        }
    }
}

- (BOOL)hasCheckInForShow:(NSObject *)show andEpisode:(NSObject *)episode
{
    // If the user did not enable check-ins, obviously we cannot know if there is a check-in
    if (![TSUserDefaults getBoolFromKey:@"MisoEnabled" withDefault:NO] ||
        ![TSUserDefaults getBoolFromKey:@"MisoCheckInEnabled" withDefault:NO]) {
        return NO;
    }
    
    // Only check check-ins for normal shows
    if ([[episode valueForKey:@"episodeSeason"] isEqualToString:@"-"] ||
        [[episode valueForKey:@"episodeNumber"] isEqualToString:@"-"] ||
        [show valueForKey:@"filters"]) {
        return NO;
    }
    
    // Retrieve the user id
    NSDictionary *userDetails = [misoBackend userDetails];
    if (!userDetails) {
        return NO;
    }
    
    // Search for it on Miso
    NSDictionary *results = [misoBackend showWithQuery:[show valueForKey:@"name"]];
    NSObject *showData = nil;
    
    // Just pick the first show (too late, I cannot even think anymore)
    for (NSObject *result in results) {
        showData = result;
        break;
    }
    if (!showData) {
        return NO;
    }
    
    // We have all the data, so search for checkins of that show!
    NSDictionary *checkins = [misoBackend checkingsForUser:[[[userDetails valueForKey:@"user"] valueForKey:@"id"] description]
                                                   andShow:[[[showData valueForKey:@"media"] valueForKey:@"id"] description]];
    
    // So check if the checkin was done
    for (NSObject *checkin in checkins) {
        if ([[[[checkin valueForKey:@"checkin"] valueForKey:@"episode_season_num"] description]
             isEqualToString:[episode valueForKey:@"episodeSeason"]] &&
            [[[[checkin valueForKey:@"checkin"] valueForKey:@"episode_num"] description]
             isEqualToString:[episode valueForKey:@"episodeNumber"]]) {
            return YES;
        }
    }
    
    return NO;
}

- (void)authenticationEnded:(BOOL)authenticated
{
    // If the shows were updated in the prefpane, we don't need to update them again
    if (!manually) {
        // Now we can check the new episodes!
        [self checkNow:nil];
        manually = YES;
    }
}

- (void)authenticatedOnMiso:(NSNotification *)inNotification
{
    // The user just login with the prefpane, so we have the credentials now!
    manually = YES;
    [misoBackend authorizeWithKey:MISO_API_KEY secret:MISO_API_SECRET];
}

- (void)checkinEpisode:(NSString *)episodeName ofShow:(NSString *)showName
{
    if ([TSUserDefaults getBoolFromKey:@"MisoEnabled" withDefault:NO] &&
        [TSUserDefaults getBoolFromKey:@"MisoCheckInEnabled" withDefault:NO]) {
        
        NSArray *seasonAndEpisode = [TSRegexFun parseSeasonAndEpisode:episodeName];
        
        if ([seasonAndEpisode count] == 3) {
            
            // Search for it on Miso
            NSDictionary *results = [misoBackend showWithQuery:showName];
            
            NSObject *show = nil;
            
            // Just pick the first show (too late, I cannot even think anymore)
            for (NSObject *result in results) {
                show = result;
                break;
            }
            
            // At this point, it should be a valid show, but maybe it is not on the Miso database yet
            if (show) {
                LogInfo(@"Adding check-in for %@ on Miso.", episodeName);
                
                [misoBackend addCheckingForShow:[[[show valueForKey:@"media"] valueForKey:@"id"] description]
                                  withSeasonNum:[TSRegexFun removeLeadingZero:[seasonAndEpisode objectAtIndex:1]]
                                     episodeNum:[TSRegexFun removeLeadingZero:[seasonAndEpisode objectAtIndex:2]]];
            }
        }
    }
}

- (NSTimeInterval) userDelay
{
    NSInteger delay;
    NSTimeInterval seconds;
    delay = [TSUserDefaults getFloatFromKey:@"checkDelay" withDefault:1];
    
    switch (delay) {
        case 0:
            // 30 minutes
            seconds = 30*60;
            break;
        case 1:
            // 1 hour
            seconds = 1*60*60;
            break;
        case 2:
            // 3 hours
            seconds = 3*60*60;
            break;
        case 3:
            // 6 hours
            seconds = 6*60*60;
            break;
        case 4:
            // 12 hours
            seconds = 12*60*60;
            break;
        case 5:
            // 1 day
            seconds = 24*60*60;
            break;
        case 6:
            // 1 day, old value, needs to be reverted back to 5
            seconds = 24*60*60;
            [TSUserDefaults setKey:@"checkDelay" fromFloat:5];
            break;
        default:
            // 1 hour
            seconds = 1*60;
    }
    
    return seconds;
}

- (void) runLoop
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSRunLoop* threadLoop = [NSRunLoop currentRunLoop];
    
    checkerLoop = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:0.1]
                                           interval:[self userDelay]
                                             target:self
                                           selector:@selector(checkAllShows)
                                           userInfo:nil
                                            repeats:YES];
    
    [threadLoop addTimer:checkerLoop forMode:NSDefaultRunLoopMode];
    [threadLoop run];
    [pool drain];
}

- (void) runLoopAfterAwake
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSRunLoop* threadLoop = [NSRunLoop currentRunLoop];
    
    // Calculate how many seconds do we have to wait until the next check
    NSTimeInterval nextCheck = [self userDelay] - [[NSDate date] timeIntervalSinceDate:
                                                   [TSUserDefaults getDateFromKey:@"lastCheckedForEpisodes"]];
    
    // If the next should already be done, do it now
    if (nextCheck < 0.1) {
        // Wait a little for connecting to the network
        nextCheck = 60;
        // Notify the user to give him some feedback
        [GrowlApplicationBridge notifyWithTitle:@"TVShows"
                                    description:TSLocalizeString(@"Checking for new episodes...")
                               notificationName:@"Checking For New Episodes"
                                       iconData:TVShowsHelperIcon
                                       priority:0
                                       isSticky:0
                                   clickContext:nil];
    }
    
    checkerLoop = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:nextCheck]
                                           interval:[self userDelay]
                                             target:self
                                           selector:@selector(checkAllShows)
                                           userInfo:nil
                                            repeats:YES];
    
    [threadLoop addTimer:checkerLoop forMode:NSDefaultRunLoopMode];
    [threadLoop run];
    [pool drain];
}

- (void) awakeFromSleep
{
    LogInfo(@"Awaked!");
    runCheck;
}

- (IBAction) checkNow:(id)sender
{
    runCheck;
}

- (void) runCheck
{
    if (checkerLoop != nil) {
        [checkerLoop performSelector:@selector(invalidate) onThread:checkerThread withObject:nil waitUntilDone:YES];
        checkerLoop = nil;
        [checkerThread release];
        checkerThread = nil;
        if (sender != nil) {
            // Notify the user to give him some feedback
            [GrowlApplicationBridge notifyWithTitle:@"TVShows"
                                        description:TSLocalizeString(@"Checking for new episodes...")
                                   notificationName:@"Checking For New Episodes"
                                           iconData:TVShowsHelperIcon
                                           priority:0
                                           isSticky:0
                                       clickContext:nil];
        }
    }
    
    // And start the thread
    checkerThread = [[NSThread alloc] initWithTarget:self selector:@selector(runLoop) object:nil];
    [checkerThread start];
}

- (void) updateShowList
{
    // Create the Preset Torrents Controller and set it with the correct delegates
    PresetTorrentsController *controller = [[PresetTorrentsController alloc] init];
    
    [controller setSubscriptionsDelegate:subscriptionsDelegate];
    [controller setPresetsDelegate:presetShowsDelegate];
    
    NSArrayController *SBArrayController = [[NSArrayController alloc] init];
    NSArrayController *PTArrayController = [[NSArrayController alloc] init];
    [SBArrayController setManagedObjectContext:[subscriptionsDelegate managedObjectContext]];
    [PTArrayController setManagedObjectContext:[presetShowsDelegate managedObjectContext]];
    [SBArrayController setEntityName:@"Subscription"];
    
    if ([SBArrayController fetchWithRequest:nil merge:YES error:nil]) {
        [controller setSBArrayController:SBArrayController];
        [controller setPTArrayController:PTArrayController];
        
        // We can now safely download the torrent show list :)
        [controller downloadTorrentShowList];
    }
    
    // Avoid a memory leak by breaking circular references between these classes 
    [controller setSBArrayController:nil];
    [controller setPTArrayController:nil];
    [controller setSubscriptionsDelegate:nil];
    [controller setPresetsDelegate:nil];
    
    [SBArrayController release];
    [PTArrayController release];
    [controller release];
}

- (void) checkAllShows
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    // First disable the menubar option
    [self performSelectorOnMainThread:@selector(disableLastCheckedItem) withObject:nil waitUntilDone:NO];
    
    // This is to track changes in the Core Data
    changed = NO;
    
    // Reload the delegates
    subscriptionsDelegate = [[SubscriptionsDelegate alloc] init];
    presetShowsDelegate = [[PresetShowsDelegate alloc] init];
    
    // Update the showlist
    [self updateShowList];
    
    // Sync shows with Miso
    if ([TSUserDefaults getBoolFromKey:@"MisoEnabled" withDefault:NO] &&
        [TSUserDefaults getBoolFromKey:@"MisoSyncEnabled" withDefault:YES]) {
        
        [self syncShows];
    }
    
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Subscription"
                                              inManagedObjectContext:[subscriptionsDelegate managedObjectContext]];
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
    [request setEntity:entity];
    
    NSError *error = nil;
    NSArray *results = [[subscriptionsDelegate managedObjectContext] executeFetchRequest:request error:&error];
    
    if (error != nil) {
        LogError(@"%@",[error description]);
    } else {
        // No error occurred so check for new episodes
        LogInfo(@"Checking for new episodes.");
        for (NSArray *show in results) {
            // Only check for new episodes if it's enabled.
            if ([[show valueForKey:@"isEnabled"] boolValue]) {
                [self checkForNewEpisodes:show];
            }
        }
    }
    
    // And free the delegates
    [subscriptionsDelegate release];
    [presetShowsDelegate release];
    subscriptionsDelegate = nil;
    presetShowsDelegate = nil;
    
    // Now that everything is done, update the time our last check was made.
    [TSUserDefaults setKey:@"lastCheckedForEpisodes" fromDate:[NSDate date]];
    
    // And update the menu to reflect the date
    [self performSelectorOnMainThread:@selector(updateLastCheckedItem) withObject:nil waitUntilDone:NO];
    
    // And warn the prefpane if needed
    if (changed) {
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"TSUpdatedShows" object:nil];
    }
    
    [pool drain];
}

- (void) checkForNewEpisodes:(NSArray *)show
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    LogDebug(@"Checking episodes for %@.", [show valueForKey:@"name"]);
    
    NSDate *pubDate, *lastDownloaded, *lastChecked;
    NSArray *episodes = [TSParseXMLFeeds parseEpisodesFromFeeds:
                         [[show valueForKey:@"url"] componentsSeparatedByString:@"#"]
                                                       maxItems:50];
    
    if ([episodes count] == 0) {
        LogDebug(@"No episodes for %@ <%@>", [show valueForKey:@"name"], [show valueForKey:@"url"]);
        [pool drain];
        return;
    }
    
    BOOL chooseAnyVersion = NO;
    
    // Get the dates before checking anything, in case we have to download more than one episode
    lastDownloaded = [show valueForKey:@"lastDownloaded"];
    lastChecked = [TSUserDefaults getDateFromKey:@"lastCheckedForEpisodes"];
    
    // Filter episodes according to user filters
    if ([show valueForKey:@"filters"] != nil) {
        episodes = [episodes filteredArrayUsingPredicate:[show valueForKey:@"filters"]];
    }
    
    NSString *lastEpisodeName = [show valueForKey:@"sortName"];
    
    // For each episode that was parsed...
    for (NSArray *episode in episodes) {
        pubDate = [episode valueForKey:@"pubDate"];
        
        // If the date we lastDownloaded episodes is before this torrent
        // was published then we should probably download the episode.
        if ([lastDownloaded compare:pubDate] == NSOrderedAscending) {
            
            // HACK HACK HACK: To avoid download an episode twice
            // Check if the sortname contains this episode name
            // HACK HACK HACK: put on the sortname the episode name
            // Why not storing this on a key? Because Core Data migrations and PrefPanes do not mix well
            NSString *episodeName = [[show valueForKey:@"name"] stringByReplacingOccurrencesOfRegex:@"^The[[:space:]]"
                                                                                         withString:@""];
            episodeName = [episodeName stringByAppendingString:[episode valueForKey:@"episodeName"]];
            
            // Detect if the last downloaded episode was aired after this one (so do not download it!)
            // Use a cache version (lastEpisodename) because we could have download it several episodes
            // in this session, for example if the show aired two episodes in the same day
            if (![TSRegexFun wasThisEpisode:episodeName airedAfterThisOne:lastEpisodeName]) {
                [pool drain];
                return;
            }
            
            // If it has been 18 hours since the episode was aired attempt the download of any version
            // Also check that we have checked for episodes at least once in the last day
            float anyVersionInterval = [TSUserDefaults getFloatFromKey:@"AnyVersionInterval" withDefault:18];
            
            if ([[NSDate date] timeIntervalSinceDate:pubDate] > anyVersionInterval*60*60 &&
                ([[NSDate date] timeIntervalSinceDate:lastChecked] < 5*60*60 ||
                 [[NSDate date] timeIntervalSinceDate:lastChecked] < (anyVersionInterval-5)*60*60)) {
                chooseAnyVersion = YES;
            } else {
                chooseAnyVersion = NO;
            }
            
            // First let's try to download the HD version from the RSS
            // Only if it is HD and HD is enabled (or SD was not available last two days)
            if (([[show valueForKey:@"quality"] boolValue] &&
                 [[episode valueForKey:@"isHD"] boolValue]) ||
                (![[show valueForKey:@"quality"] boolValue] &&
                 ![[episode valueForKey:@"isHD"] boolValue]) ||
                chooseAnyVersion) {
                
                BOOL downloaded = NO;
                
                // If the user has Miso enabled, check if there is a check-in for that episode
                if ([self hasCheckInForShow:show andEpisode:episode]) {
                    LogInfo(@"There is already a checkin for this episode, so it will not be downloaded.");
                    downloaded = YES;
                }
                
                // Otherwise download the episode! With mirrors (they are stored in a string separated by #)
                if (!downloaded && [TSTorrentFunctions downloadEpisode:episode ofShow:show]) {
                    downloaded = YES;
                    
                    // Checkin the episode on Miso
                    [self checkinEpisode:[episode valueForKey:@"episodeName"] ofShow:[show valueForKey:@"name"]];
                }
                
                // Update the last downloaded episode name only if it was aired after the previous stored one
                if (downloaded) {
                    if ([TSRegexFun wasThisEpisode:episodeName
                                 airedAfterThisOne:[show valueForKey:@"sortName"]]) {
                        [show setValue:pubDate forKey:@"lastDownloaded"];
                        [show setValue:episodeName forKey:@"sortName"];
                        [[subscriptionsDelegate managedObjectContext] processPendingChanges];
                        [subscriptionsDelegate saveAction];
                        changed = YES;
                    }
                }
            }
        } else {
            // The rest is not important because it is even before the previous entry
            [pool drain];
            return;
        }
        
    }
    
    [pool drain];
}

#pragma mark -
#pragma mark Status Menu
- (void) activateStatusMenu
{
    statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
    
    [statusItem setImage:[NSImage imageNamed:@"TVShows-Menu-Icon-Black"]];
    [statusItem setAlternateImage:[NSImage imageNamed:@"TVShows-Menu-Icon-White"]];
    [statusItem setEnabled:YES];
    [statusItem setHighlightMode:YES];
    [statusItem setTarget:self];
    
    [statusItem setAction:@selector(openApplication:)];
    [statusItem setMenu:statusMenu];
    
    // Localize
    [lastUpdateItem setTitle:[NSString stringWithFormat:@"%@ %@", TSLocalizeString(@"Last Checked:"), TSLocalizeString(@"Never")]];
    [checkShowsItem setTitle:TSLocalizeString(@"Checking now, please wait...")];
    [subscriptionsItem setTitle:[NSString stringWithFormat:@"%@...", TSLocalizeString(@"Subscriptions")]];
    [syncItem setTitle:[NSString stringWithFormat:@"%@...", TSLocalizeString(@"Sync")]];
    [preferencesItem setTitle:[NSString stringWithFormat:@"%@...", TSLocalizeString(@"Preferences")]];
    [feedbackItem setTitle:[NSString stringWithFormat:@"%@...", TSLocalizeString(@"Submit Feedback")]];
    [aboutItem setTitle:[NSString stringWithFormat:@"%@ TVShows", TSLocalizeString(@"About")]];
    [disableItem setTitle:TSLocalizeString(@"Disable TVShows")];
}

- (void) disableLastCheckedItem
{
    // Disable the menubar option
    [checkShowsItem setAction:nil];
    [checkShowsItem setTitle:TSLocalizeString(@"Checking now, please wait...")];
}

- (void) updateLastCheckedItem
{
    // We have to build a localized string with the date info
    // Prepare the date formatter
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    [dateFormatter setDateStyle:NSDateFormatterNoStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    
    // Create the string from this date
    NSString *formattedDateString = [dateFormatter stringFromDate:[TSUserDefaults getDateFromKey:@"lastCheckedForEpisodes"]];
    
    // Finally, update the string
    [lastUpdateItem setTitle:[NSString stringWithFormat:@"%@ %@", TSLocalizeString(@"Last Checked:"), formattedDateString]];
    
    // Enable again the menubar option
    [checkShowsItem setAction:@selector(checkNow:)];
    [checkShowsItem setTitle:TSLocalizeString(@"Check for new episodes now")];
}

- (IBAction) openApplication:(id)sender
{
    BOOL success = [[NSWorkspace sharedWorkspace] openFile:
                    [[[NSBundle bundleWithIdentifier:TVShowsAppDomain] bundlePath] stringByExpandingTildeInPath]];
    
    if (!success) {
        LogError(@"Application did not open at request.");
    }
}

- (void) openTab:(NSInteger)tabNumber
{
    NSString *command = [NSString stringWithFormat:
                         @"tell application \"System Preferences\"                               \n"
                         @"   activate                                                           \n"
                         @"   set the current pane to pane id \"com.victorpimentel.TVShows2\"    \n"
                         @"end tell                                                              \n"
                         @"tell application \"System Events\"                                    \n"
                         @"    tell process \"System Preferences\"                               \n"
                         @"        click radio button %d of tab group 1 of window \"TVShows\"    \n"
                         @"    end tell                                                          \n"
                         @"end tell                                                    ", tabNumber];
    
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:@"/usr/bin/osascript"];
    [task setArguments:[NSMutableArray arrayWithObjects:@"-e", command, nil]];
    [task launch];
}

- (IBAction) showSubscriptions:(id)sender
{
    [self openTab:1];
}

- (IBAction) showSync:(id)sender
{
    [self openTab:2];
}

- (IBAction) showPreferences:(id)sender
{
    [self openTab:3];
}

- (IBAction) showAbout:(id)sender
{
    [self openTab:4];
}

- (IBAction) showFeedback:(id)sender
{
    NSString *command =
    @"tell application \"System Preferences\"                               \n"
    @"   activate                                                           \n"
    @"   set the current pane to pane id \"com.victorpimentel.TVShows2\"    \n"
    @"end tell                                                              \n"
    @"tell application \"System Events\"                                    \n"
    @"    tell process \"System Preferences\"                               \n"
    @"        click button 4 of window \"TVShows\"                          \n"
    @"    end tell                                                          \n"
    @"end tell                                                              ";
    
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:@"/usr/bin/osascript"];
    [task setArguments:[NSMutableArray arrayWithObjects:@"-e", command, nil]];
    [task launch];
}

- (IBAction) quitHelper:(id)sender
{
    [[[PreferencesController new] autorelease] enabledControlDidChange:NO];
    [NSApp terminate];
}

#pragma mark -
#pragma mark Sparkle Delegate Methods
- (void) updater:(SUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)update
{
    // We use this to help no whether or not the TVShowsHelper should close after
    // downloading new episodes or whether it should wait for Sparkle to finish
    // installing new updates.
    LogDebug(@"Sparkle found a valid update.");
    
    // If the user has automatic updates turned on, set a value saying that we installed
    // an update in the background and send a Growl notification.
    if ([TSUserDefaults getBoolFromKey:@"SUAutomaticallyUpdate" withDefault:YES]) {
        [TSUserDefaults setKey:@"AutomaticallyInstalledLastUpdate" fromBool:YES];
        
        if([TSUserDefaults getBoolFromKey:@"GrowlOnAppUpdate" withDefault:YES]) {
            [GrowlApplicationBridge notifyWithTitle:@"TVShows Update Downloading"
                                        description:TSLocalizeString(@"A new version of TVShows is being downloaded and installed.")
                                   notificationName:@"TVShows Update Downloaded"
                                           iconData:TVShowsHelperIcon
                                           priority:0
                                           isSticky:0
                                       clickContext:nil];
        }
    } else if([TSUserDefaults getBoolFromKey:@"GrowlOnAppUpdate" withDefault:YES]) {
        [GrowlApplicationBridge notifyWithTitle:@"TVShows Update Available"
                                    description:TSLocalizeString(@"A new version of TVShows is available for download.")
                               notificationName:@"TVShows Update Available"
                                       iconData:TVShowsHelperIcon
                                       priority:0
                                       isSticky:YES
                                   clickContext:nil];
    }
}

- (void) dealloc
{
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    [checkerLoop invalidate];
    [checkerLoop release];
    [TVShowsHelperIcon release];
    [misoBackend release];
    [subscriptionsDelegate release];
    [presetShowsDelegate release];
    [super dealloc];
}

@end
