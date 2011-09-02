//
//  OpenUDID.m
//  openudid
//
//  Created by Yann Lechelle (cofounder Appsfire) on 8/28/11.
//  Copyright 2011 OpenUDID.com
//

/*
 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
*/


#import "OpenUDID.h"
#import <CommonCrypto/CommonDigest.h> // Need to import for CC_MD5 access
#import <UIKit/UIPasteboard.h>

static NSString * const kOpenUDID = @"com.OpenUDID.pboard";

@interface OpenUDID (Private)
+ (NSString*) _getOpenUDID;
@end

@implementation OpenUDID

// private method to return the OpenUDID
//
+ (NSString*) _getOpenUDID {
    
    NSString* _openUDID = nil;
    
    // One day, this may no longer be allowed. When that is, just comment this line out.
    //
    _openUDID = [[UIDevice currentDevice] uniqueIdentifier];

    
    // Take this opportunity to give the simulator a proper UDID (i.e. nullify UDID and create an OpenUDID)
    //
#if TARGET_IPHONE_SIMULATOR
    _openUDID = nil;
#endif
    
    // Next we try to use an alternative method which uses the host name, process ID, and a time stamp
    // We then hash it with md5 to get 32 bytes, and then add 4 extra random bytes
    // Collision is possible of course, but unlikely and suitable for most industry needs (e.g.. aggregate trackin)
    //
    if (_openUDID==nil) {
        unsigned char result[16];
        const char *cStr = [[[NSProcessInfo processInfo] globallyUniqueString] UTF8String];
        CC_MD5( cStr, strlen(cStr), result );
        _openUDID = [NSString stringWithFormat:
                @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%08x",
                result[0], result[1], result[2], result[3], 
                result[4], result[5], result[6], result[7],
                result[8], result[9], result[10], result[11],
                result[12], result[13], result[14], result[15],
                arc4random() % 4294967295];  
    }
    
    // Call to other developers in the Open Source community:
    // feel free to add better or alternative "UDID" methods here.

    return _openUDID;
}


// Main public method that returns the OpenUDID
// This method will generate and store the OpenUDID if it doesn't exist
// It will return the null udid (forty zeros) if the user has somehow opted-out this app (this is subject to 3rd party implementation)
// Otherwise, it will register the current app and return the OpenUDID
//
+ (NSString*) value {
    NSString *bundleid = [[NSBundle mainBundle] bundleIdentifier];
    UIPasteboard* openUDIDPasteboard = [UIPasteboard pasteboardWithName:kOpenUDID create:YES];
    [openUDIDPasteboard setPersistent:YES];
    id item = [openUDIDPasteboard dataForPasteboardType:kOpenUDID];
    NSMutableDictionary* dict = item && [item isKindOfClass:[NSDictionary class]]
        ? [NSMutableDictionary dictionaryWithDictionary:[NSKeyedUnarchiver unarchiveObjectWithData:item]]
        : nil;
    // NSLog(@"OpenUDID: dict %@",dict);
    
    // First check if the current bundleid is registered
    //
    NSString* bundleidOptOut = [dict objectForKey:bundleid];
	if (bundleidOptOut==nil) {		
        // bundleid could not be found, so let's register it
        // R is for registered, O is for opted-out...
        // NSLog(@"OpenUDID: Registering %@",bundleid);
        [dict setValue:@"R" forKey:bundleid];
        [openUDIDPasteboard setData:[NSKeyedArchiver archivedDataWithRootObject:dict] forPasteboardType:kOpenUDID];
    } else if ([bundleidOptOut isEqualToString:@"O"]) {
            // This app is opted-out, let's return the phantom OpenUDID (a bunch of zeros really - 40 to be exact)
            // Developers need to take this *new* case into considerations and manage without a UDID at all... #privacy
            return [NSString stringWithFormat:@"%040x",0];
    }
    
    // Now, let's access the OpenUDID
    NSString* openUDID = [dict objectForKey:kOpenUDID];
    
    // Can't find it, let's generate and store
	if (openUDID==nil) {
        //NSLog(@"OpenUDID: Generate and store");
        openUDID = [OpenUDID _getOpenUDID];
        [dict setValue:openUDID forKey:kOpenUDID];
        [openUDIDPasteboard setData:[NSKeyedArchiver archivedDataWithRootObject:dict] forPasteboardType:kOpenUDID];
        return openUDID;
    }
    
    //NSLog(@"OpenUDID: %@ found",openUDID );
    return openUDID;
}

@end
