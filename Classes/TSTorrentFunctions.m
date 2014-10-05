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

#import "TSTorrentFunctions.h"

#import <Growl/GrowlApplicationBridge.h>

#import "AppInfoConstants.h"
#import "TSUserDefaults.h"
#import "TSRegexFun.h"
#import "TorrentzParser.h"
#import "WebsiteFunctions.h"
#import "TheTVDB.h"

@implementation TSTorrentFunctions

+ (BOOL) dataIsValidTorrent:(NSData *)data
{
    // First check if the data is there
    if (!data) {
        return NO;
    }
    
    // Convert to a .torrent file and check if the header is correct
    NSString *string = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    if ([[string substringToIndex:11] isEqualToString:@"d8:announce"]) {
        [string release];
        return YES;
    } else {
        [string release];
        return NO;
    }
}

+ (BOOL) downloadEpisode:(NSObject *)episode ofShow:(NSObject *)show
{
    NSString *episodeName = [episode valueForKey:@"episodeName"];
    NSArray *urls = [[episode valueForKey:@"link"] componentsSeparatedByString:@"#"];
    NSString *showName = nil;
    LogInfo(@"Downloading %@.", [episode valueForKey:@"link"]);

    // Choose the show name (it can be in two keys depending if the show is a preset or a subscription)
    if ([[show valueForKey:@"name"] rangeOfString:@"http"].location == NSNotFound) {
        showName = [show valueForKey:@"name"];
    } else {
        showName = [show valueForKey:@"displayName"];
    }
    
    // Look for the torrent in Torrentz if it is not found
    if ([[urls objectAtIndex:0] rangeOfString:@"http"].location == NSNotFound &&
        [[urls objectAtIndex:0] rangeOfString:@"magnet:"].location == NSNotFound) {
        LogInfo(@"Retrieving an HD torrent file from Torrentz of: %@", episodeName);
        NSString *url = [TorrentzParser getAlternateTorrentForEpisode:episodeName];
        if (url == nil) {
            LogError(@"Unable to find an HD torrent file for: %@", episodeName);
            
            // The difference between the prefpane and the helper app is that in the prefpane
            // we should warn the user and give him the possibility to download the SD version
#if PREFPANE
            // If the user doesn't want to download the SD version, just return!
            if (![self shouldDownloadSDForEpisode:episodeName]) {
                return NO;
            } else {
                // Otherwise remove the placeholder
                NSMutableArray *copy = [NSMutableArray arrayWithArray:urls];
                [copy removeObjectAtIndex:0];
                urls = copy;
            }
#else
            return NO;
#endif
        } else {
            // Otherwise replace the placeholder with the good link
            NSMutableArray *copy = [NSMutableArray arrayWithArray:urls];
            [copy replaceObjectAtIndex:0 withObject:url];
            urls = copy;
        }
    }
    
    NSString *saveLocation = [self saveLocationForEpisode:episode ofShow:showName];
    
    LogInfo(@"Attempting to download new episode: %@", episodeName);
    
    // Process all urls until the torrent is properly downloaded
    for (NSString *url in urls) {
        
        // First try magnets
        if ([url rangeOfString:@"magnet:"].location != NSNotFound) {
            
            // Just open it
            // Open magnet links without bring app that handles them to the foreground
            NSArray* urls = [NSArray arrayWithObject:[url stringByReplacingOccurrencesOfString:@" " withString:@"%20"]];
            [[NSWorkspace sharedWorkspace] openURLs:urls withAppBundleIdentifier:nil 
                options:NSWorkspaceLaunchWithoutActivation additionalEventParamDescriptor:nil launchIdentifiers:nil];
            
#if HELPER_APP
            if([TSUserDefaults getBoolFromKey:@"GrowlOnNewEpisode" withDefault:1]) {
                NSData *cover = [[NSData alloc] initWithData:
                                 [[TheTVDB getPosterForShow:showName
                                                 withShowID:[[show valueForKey:@"tvdbID"] description]
                                                 withHeight:96 withWidth:66] TIFFRepresentation]];
                
                [GrowlApplicationBridge notifyWithTitle:[NSString stringWithFormat:@"%@", showName]
                                            description:[NSString stringWithFormat:TSLocalizeString(@"A new episode of %@ is being downloaded."), showName]
                                       notificationName:@"New Episode Downloaded"
                                               iconData:cover
                                               priority:0
                                               isSticky:0
                                           clickContext:nil];
                [cover autorelease];
            }
#endif
            
            // Success!
            return YES;
        }
        
        // Fix BT-chat Links
        if ([url rangeOfString:@"bt-chat"].location != NSNotFound) {
            url = [url stringByAppendingString:@"&type=torrent"];
        }
        
        // Download the file
        NSData *fileContents = [WebsiteFunctions downloadDataFrom:url];
        
        // Check if the download was right
        if (!fileContents || ![self dataIsValidTorrent:fileContents]) {
            LogError(@"Unable to download file: %@ <%@>", episodeName, url);
        } else {
            
            // Write the data into a .torrent file and see if the file could be created
            if (![fileContents writeToFile:saveLocation atomically:YES]) {
                LogError(@"Unable to store .torrent file: %@ <%@>", episodeName, saveLocation);
                return NO;
            }
            
            // The file downloaded successfully, continuing...
            LogInfo(@"Episode downloaded successfully: %@ <%@>", episodeName, url);
            
            // Bounce the downloads stack!
            [[NSDistributedNotificationCenter defaultCenter]
             postNotificationName:@"com.apple.DownloadFileFinished" object:saveLocation];
            
            // Check to see if the user wants to automatically open new downloads
            if([TSUserDefaults getBoolFromKey:@"AutoOpenDownloadedFiles" withDefault:YES]) {
                [[NSWorkspace sharedWorkspace] openFile:saveLocation withApplication:nil andDeactivate:NO];
            }
            
#if HELPER_APP
            if([TSUserDefaults getBoolFromKey:@"GrowlOnNewEpisode" withDefault:YES]) {
                NSData *cover = [[NSData alloc] initWithData:
                                 [[TheTVDB getPosterForShow:showName
                                                 withShowID:[[show valueForKey:@"tvdbID"] description]
                                                 withHeight:96 withWidth:66] TIFFRepresentation]];
                
                [GrowlApplicationBridge notifyWithTitle:[NSString stringWithFormat:@"%@", showName]
                                            description:[NSString stringWithFormat:TSLocalizeString(@"A new episode of %@ is being downloaded."), showName]
                                       notificationName:@"New Episode Downloaded"
                                               iconData:cover
                                               priority:0
                                               isSticky:0
                                           clickContext:nil];
                [cover autorelease];
            }
#endif
            
            // Success!
            return YES;
        }
    }
    
    // No URL was a correct .torrent file :(
    return NO;
}

+ (BOOL) shouldDownloadSDForEpisode:(NSString *)episodeName
{
    // Get the user default. If there is no preference, use a "third" value
    BOOL shouldDownloadSD = [TSUserDefaults getFloatFromKey:@"AutoDownloadFallbackSD" withDefault:ShowWarning];
    
    // Display the warning if the user did not want to hide it
    if (shouldDownloadSD == ShowWarning) {
        // Display the error
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:TSLocalizeString(@"Download SD")];
        [alert addButtonWithTitle:TSLocalizeString(@"Cancel")];
        [alert setShowsSuppressionButton:YES];
        [alert setMessageText:[NSString stringWithFormat:TSLocalizeString(@"Unable to find an HD torrent for %@"),
                               episodeName]];
        [alert setInformativeText:TSLocalizeString(@"The file may not be released yet. Please try again later or check your internet connection. Alternatively you can download the SD version.")];
        [alert setAlertStyle:NSWarningAlertStyle];
        
        // Run the alert and then wait for user input.
        shouldDownloadSD = ([alert runModal] == NSAlertFirstButtonReturn);
        
        // Remember the selected option for next time if the user wants to hide the warning
        if ([[alert suppressionButton] state]) {
            [TSUserDefaults setKey:@"AutoDownloadFallbackSD" fromInt:shouldDownloadSD];
        }
        [alert release];
    }
    
    return shouldDownloadSD;
}

+ (NSString *) saveLocationForEpisode:(NSObject *)episode ofShow:(NSString *)showName
{
    // Retrieve the saving folder
    NSString *saveLocation = [TSUserDefaults getStringFromKey:@"downloadFolder"];
    
    // Check if we have to sort shows by folders or not
    if ([TSUserDefaults getBoolFromKey:@"SortInFolders" withDefault:NO]) {
        saveLocation = [saveLocation stringByAppendingPathComponent:
                        [[showName stringByReplacingOccurrencesOfString:@": " withString:@" "]
                         stringByReplacingOccurrencesOfString:@":" withString:@" "]];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:saveLocation
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:nil]) {
            LogError(@"Unable to create the folder: %@", saveLocation);
            return nil;
        }
        // And check if we have to go deeper (sorting by season)
        if ([TSUserDefaults getBoolFromKey:@"SeasonSubfolders" withDefault:NO]) {
            if (![[episode valueForKey:@"episodeSeason"] isEqualTo:@"-"]) {
                saveLocation = [saveLocation stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"Season %@",
                                 [TSRegexFun removeLeadingZero:[episode valueForKey:@"episodeSeason"]]]];
                if (![[NSFileManager defaultManager] createDirectoryAtPath:saveLocation
                                               withIntermediateDirectories:YES
                                                                attributes:nil
                                                                     error:nil]) {
                    LogError(@"Unable to create the folder: %@", saveLocation);
                    return nil;
                }
            }
        }
    }
    
    // Add the filename
    saveLocation = [saveLocation stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.torrent",
                     [[[episode valueForKey:@"episodeName"]
                       stringByReplacingOccurrencesOfString:@": " withString:@" "]
                      stringByReplacingOccurrencesOfString:@":" withString:@" "]]];
    
    return saveLocation;
}

+ (NSString *) getTorrentFileFromMagnetLink:(NSString *)aMagnetLink
{
    NSString *magnetHash = [TSRegexFun parseHashFromMagnetLink:aMagnetLink];
    
    return [TSTorrentFunctions getTorrentFileFromMagnetHash:magnetHash];
}

+ (NSString *) getTorrentFileFromMagnetHash:(NSString *)aMagnetHash
{
    return [NSString stringWithFormat:@"https://torcache.net/torrent/%@.torrent", aMagnetHash];
}

@end
