/*
 Created on 28/02/2009
 Copyright 2009 Max Howell <max@methylblue.com>
 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <Cocoa/Cocoa.h>
#import <PreferencePanes/PreferencePanes.h>


@interface MBSliderButton : NSControl <NSAnimationDelegate>
{   
    NSPoint location;
    IBOutlet NSPreferencePane* prefpane;
    NSImage* knob;
    NSImage* surround;   
    bool state;
}

-(IBAction)moveLeft:(id)sender;
-(IBAction)moveRight:(id)sender;

-(NSInteger)state;
-(void)setState:(NSInteger)newstate;
-(void)setState:(NSInteger)newstate animate:(bool)animate;

@end
