/*
 Copyright (c) 2006-2007 by Logan Rockmore Design, http://www.loganrockmore.com/
 
 Permission is hereby granted, free of charge, to any person obtaining a
 copy of this software and associated documentation files (the "Software"),
 to deal in the Software without restriction, including without limitation
 the rights to use, copy, modify, merge, publish, distribute, sublicense,
 and/or sell copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 THE COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
 OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

#import "LROverflowButton.h"


@implementation LROverflowButton

- (id) init {
	self = [super init];
	if (self != nil) {
		
        NSImage* imageToSet = [[[NSImage alloc] initByReferencingFile:
                                [[NSBundle bundleForClass:[self class]] pathForResource:@"OverflowButton"
                                                                                 ofType:@"tif"]] autorelease];
		[self setImage:imageToSet];
		[self setBordered:NO];
		[self sizeToFit];
		
	}
	return self;
}


- (void)displayMenu:(NSTimer *)theTimer
{
	NSEvent *theEvent=[timer userInfo];
	
	int yCoordinate = [[self superview] frame].origin.y + [self frame].origin.y;
	
	NSEvent *click = [NSEvent mouseEventWithType:[theEvent type] location:NSMakePoint([self frame].origin.x, yCoordinate) modifierFlags:[theEvent modifierFlags] timestamp:[theEvent timestamp] windowNumber:[theEvent windowNumber] context:[theEvent context] eventNumber:[theEvent eventNumber] clickCount:[theEvent clickCount] pressure:[theEvent pressure]]; 
	[NSMenu popUpContextMenu:[self menu] withEvent:click forView:self];
	[timer invalidate];
}   

- (void)mouseDown:(NSEvent *)theEvent 
{ 
	[self highlight:NO];
    NSImage* imageToSet = [[[NSImage alloc] initByReferencingFile:
                            [[NSBundle bundleForClass:[self class]] pathForResource:@"OverflowButtonPressed"
                                                                             ofType:@"tif"]] autorelease];
	[self setImage:imageToSet];
	timer=[NSTimer timerWithTimeInterval:0.0 target:self selector:@selector(displayMenu:) userInfo:theEvent repeats:NO];
	[[NSRunLoop currentRunLoop] addTimer:timer forMode:@"NSDefaultRunLoopMode"];	
} 

- (void)mouseUp:(NSEvent *)theEvent 
{ 
	[self highlight:NO];
    NSImage* imageToSet = [[[NSImage alloc] initByReferencingFile:
      [[NSBundle bundleForClass:[self class]] pathForResource:@"OverflowButton"
                                                       ofType:@"tif"]] autorelease];
	[self setImage:imageToSet];
} 

@end
