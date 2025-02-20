//
//  Tweak.m
//  FLEXing
//
//  Created by Tanner Bennett on 2016-07-11
//  Copyright © 2016 Tanner Bennett. All rights reserved.
//


#import "Interfaces.h"
#include <roothide.h>

BOOL initialized = NO;
id manager = nil;
SEL show = nil;

static NSHashTable *windowsWithGestures = nil;

static id (*FLXGetManager)();
static SEL (*FLXRevealSEL)();
static Class (*FLXWindowClass)();

/// This isn't perfect, but works for most cases as intended
inline bool isLikelyUIProcess() {
    NSString *executablePath = NSProcessInfo.processInfo.arguments[0];

    return ([executablePath hasPrefix:@"/var/containers/Bundle/Application/"] && strstr(executablePath.UTF8String,".app/"))  ||
        (strstr(executablePath.UTF8String,"/Applications/") && strstr(executablePath.UTF8String,".app/")) ||
        [executablePath hasSuffix:@"CoreServices/SpringBoard.app/SpringBoard"];
}

inline bool isSnapchatApp() {
    // See: near line 44 below
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.toyopagroup.picaboo"];
}

inline BOOL flexAlreadyLoaded() {
    return NSClassFromString(@"FLEXExplorerToolbar") != nil;
} 

%group AppHook
%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    %orig;

    if (!initialized) {
        return;
    }

    if (event.type == UIEventTypeTouches) {
        NSSet *touches = [event allTouches];

        //NSLog(@"FLEXing sendEvent type=%d, count=%d", event.type, touches.count);
    
        if (touches.count == 3) {
            BOOL allTouchesBegan = YES;
            int i=0;
            // for (UITouch *touch in touches) {
            //     NSLog(@"FLEXing touch[%d] phase=%d", i++, touch.phase);
            // }
            for (UITouch *touch in touches) {
                if (touch.phase != UITouchPhaseBegan && touch.phase != UITouchPhaseStationary) {
                    allTouchesBegan = NO;
                    break;
                }
            }
            if (allTouchesBegan) {
                NSLog(@"FLEXing sendEvent start");
                [self performSelector:@selector(flexHandleThreeFingerLongPress) withObject:nil afterDelay:0.5];
            } else {
                BOOL allTouchesEndedOrCancelled = NO;
                for (UITouch *touch in touches) {
                    if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                        allTouchesEndedOrCancelled = YES;
                        break;
                    }
                }
                if (allTouchesEndedOrCancelled) {
                    NSLog(@"FLEXing sendEvent cancel");
                    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flexHandleThreeFingerLongPress) object:nil];
                }
            }
        }
    }
}

%new
- (void)flexHandleThreeFingerLongPress {
    NSLog(@"FLEXing flexHandleThreeFingerLongPress");
    [manager performSelector:show];
}
%end
%end

%ctor {
    NSString *standardPath = jbroot(@"/Library/MobileSubstrate/DynamicLibraries/libFLEX.dylib");
    NSString *reflexPath =   jbroot(@"/Library/MobileSubstrate/DynamicLibraries/libreflex.dylib");
    NSFileManager *disk = NSFileManager.defaultManager;
    NSString *libflex = nil;
    NSString *libreflex = nil;
    void *handle = nil;

    if ([disk fileExistsAtPath:standardPath]) {
        libflex = standardPath;
        if ([disk fileExistsAtPath:reflexPath]) {
            libreflex = reflexPath;
        }
    } else {
        // Check if libFLEX resides in the same folder as me
        NSString *executablePath = NSProcessInfo.processInfo.arguments[0];
        NSString *whereIam = executablePath.stringByDeletingLastPathComponent;
        NSString *possibleFlexPath = [whereIam stringByAppendingPathComponent:@"Frameworks/libFLEX.dylib"];
        NSString *possibleRelexPath = [whereIam stringByAppendingPathComponent:@"Frameworks/libreflex.dylib"];
        if ([disk fileExistsAtPath:possibleFlexPath]) {
            libflex = possibleFlexPath;
            if ([disk fileExistsAtPath:possibleRelexPath]) {
                libreflex = possibleRelexPath;
            }
        } else {
            // libFLEX not found
            // ...
        }
    }

    if (libflex) {
        // Hey Snapchat / Snap Inc devs,
        // This is so users don't get their accounts locked.
        if (isLikelyUIProcess() && !isSnapchatApp()) {
            handle = dlopen(libflex.UTF8String, RTLD_LAZY);
            // NSLog(@"FLEXing libFlex=%p", handle);
            
            if (libreflex) {
                dlopen(libreflex.UTF8String, RTLD_NOW);
            }
        }
    }

    if (handle || flexAlreadyLoaded()) {
        // FLEXing.dylib itself does not hard-link against libFLEX.dylib,
        // instead libFLEX.dylib provides getters for the relevant class
        // objects so that it can be updated independently of THIS tweak.
        FLXGetManager = (id(*)())dlsym(handle, "FLXGetManager");
        FLXRevealSEL = (SEL(*)())dlsym(handle, "FLXRevealSEL");
        FLXWindowClass = (Class(*)())dlsym(handle, "FLXWindowClass");

        if (FLXGetManager && FLXRevealSEL) {
            manager = FLXGetManager();
            show = FLXRevealSEL();

            windowsWithGestures = [NSHashTable weakObjectsHashTable];
            initialized = YES;
        }
    }

    if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        %init(AppHook);
    }
    %init;
}

%hook UIWindow
- (BOOL)_shouldCreateContextAsSecure {
    return (initialized && [self isKindOfClass:FLXWindowClass()]) ? YES : %orig;
}

%new
- (void)flexGestureHandler:(UILongPressGestureRecognizer *)recognizer {
    NSLog(@"FLEXing flexGestureHandler=%@", self);
    [manager performSelector:show];
}

- (void)becomeKeyWindow {
    %orig;

    if (!initialized) {
        return;
    }

    BOOL needsGesture = ![windowsWithGestures containsObject:self];
    BOOL isFLEXWindow = [self isKindOfClass:FLXWindowClass()];
    BOOL isStatusBar  = [self isKindOfClass:[UIStatusBarWindow class]];
    NSLog(@"FLEXing becomeKeyWindow=%@/%p %d,%d,%d", [self class], self, needsGesture , !isFLEXWindow , !isStatusBar);
    if (needsGesture && !isFLEXWindow && !isStatusBar) {
        [windowsWithGestures addObject:self];

        // Add 3-finger long-press gesture for apps without a status bar
        UILongPressGestureRecognizer *tap = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(flexGestureHandler:)];
        tap.minimumPressDuration = .5;
        tap.numberOfTouchesRequired = 3;

        [self addGestureRecognizer:tap];
    }
}
%end

%hook UIStatusBarWindow
- (id)initWithFrame:(CGRect)frame {
    self = %orig;
    
    NSLog(@"FLEXing UIStatusBarWindow=%d", initialized);
    if (initialized) {
        // Add long-press gesture to status bar
        [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:manager action:show]];
    }
    
    return self;
}
%end

%hook FLEXExplorerViewController
- (BOOL)_canShowWhileLocked {
    return YES;
}
%end

/*
%hook _UISheetPresentationController
- (id)initWithPresentedViewController:(id)present presentingViewController:(id)presenter {
    self = %orig;
    if ([present isKindOfClass:%c(FLEXNavigationController)]) {
        NSLog(@"FLEXing initWithPresentedViewController=%@", self);
        // Enable half height sheet
        //invliad on ios15 //self._presentsAtStandardHalfHeight = YES;
        // Start fullscreen, 0 for half height
        self._indexOfCurrentDetent = 1;
        // Don't expand unless dragged up
        self._prefersScrollingExpandsToLargerDetentWhenScrolledToEdge = NO;
        // Don't dim first detent
        self._indexOfLastUndimmedDetent = 1; //???crash on ios15
    }
    
    return self;
}
%end
*/

%hook FLEXManager
%new
+ (NSString *)dlopen:(NSString *)path {
    if (!dlopen(path.UTF8String, RTLD_NOW)) {
        return @(dlerror());
    }
    
    return @"OK";
}
%end
