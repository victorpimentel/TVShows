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

#import "ValueTransformers.h"
#import "TheTVDB.h"


@implementation ShowPosterValueTransformer

+ (Class) transformedValueClass;
{
    return [NSImage class];
}

+ (BOOL) allowsReverseTransformation
{
    return NO;
}

- (id) transformedValue:(id)value
{
    // For some reason, we sometimes receive nil values.
    // Those will crash the program if we aren't careful.
    if (value == nil) return nil;
    
    NSImage *showPoster = [TheTVDB getPosterForShow:[value valueForKey:@"name"]
                                         withShowID:[NSString stringWithFormat:@"%@",
                                                     [value valueForKey:@"tvdbID"]]
                                         withHeight:94
                                          withWidth:66];
    return showPoster;
}

@end

@implementation CancelledShowValueTransformer

+ (Class) transformedValueClass;
{
    return [NSNumber class];
}

+ (BOOL) allowsReverseTransformation
{
    return NO;
}

- (id) transformedValue:(id)value
{
    // For some reason, we sometimes receive nil values.
    // Those will crash the program if we aren't careful.
    if (value == nil || [value isEqualToString:@""]) {
        return [NSNumber numberWithBool:NO];
    } else {
        return [NSNumber numberWithBool:YES];
    }
}

@end

static NSDate *TSLastDateEmptySubscriptions = nil;

@implementation EmptySubscriptionsValueTransformer

+ (Class) transformedValueClass;
{
    return [NSNumber class];
}

+ (BOOL) allowsReverseTransformation
{
    return NO;
}

- (id) transformedValue:(id)value
{
    if (TSLastDateEmptySubscriptions == nil) {
        TSLastDateEmptySubscriptions = [[NSDate date] retain];
    }
    
    // For some reason, we sometimes receive nil values.
    // Those will crash the program if we aren't careful.
    // Check also that the last time someone ask for this was more than 500 ms
    // to avoid false positives
    if (value == nil || [value count] > 0 ||
        [[NSDate date] timeIntervalSinceDate:TSLastDateEmptySubscriptions] < 0.5) {
        [TSLastDateEmptySubscriptions release];
        TSLastDateEmptySubscriptions = [[NSDate date] retain];
        return [NSNumber numberWithBool:YES];
    } else {
        [TSLastDateEmptySubscriptions release];
        TSLastDateEmptySubscriptions = [[NSDate date] retain];
        return [NSNumber numberWithBool:NO];
    }
}

@end
