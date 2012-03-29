//
//  OpenUDID.m
//  openudid
//
//  initiated by Yann Lechelle (cofounder Appsfire) on 8/28/11.
//  Copyright 2011 OpenUDID.org
//
//  iOS / MacOS code: https://github.com/ylechelle/OpenUDID
//  Android code: https://github.com/vieux/OpenUDID
//
//  Contributors:
//      https://github.com/ylechelle (initiator & iOS code)
//      https://github.com/samrobbins (Mac OS port)
//      https://github.com/vieux (Android version)

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

#pragma mark -
#pragma mark Apple KeychainItemWrapper declaration - Included inline

/*
 The KeychainItemWrapper class is an abstraction layer for the iPhone Keychain communication. It is merely a 
 simple wrapper to provide a distinct barrier between all the idiosyncracies involved with the Keychain
 CF/NS container objects.
 */
@interface KeychainItemWrapper : NSObject
{
    NSMutableDictionary *keychainItemData;      // The actual keychain item data backing store.
    NSMutableDictionary *genericPasswordQuery;  // A placeholder for the generic keychain item query used to locate the item.
}

@property (nonatomic, retain) NSMutableDictionary *keychainItemData;
@property (nonatomic, retain) NSMutableDictionary *genericPasswordQuery;

// Designated initializer.
- (id)initWithIdentifier: (NSString *)identifier accessGroup:(NSString *) accessGroup;
- (void)setObject:(id)inObject forKey:(id)key;
- (id)objectForKey:(id)key;

// Initializes and resets the default generic keychain item data.
- (void)resetKeychainItem;

@end

#pragma mark - 


#import "OpenUDID.h"
#import <CommonCrypto/CommonDigest.h> // Need to import for CC_MD5 access

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
#import <UIKit/UIPasteboard.h>
#import <UIKit/UIKit.h>
#else
#import <AppKit/NSPasteboard.h>
#endif

//#define OpenUDIDLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
//#define OpenUDIDLog(fmt, ...) NSLog((@"[Line %d] " fmt), __LINE__, ##__VA_ARGS__);
#define OpenUDIDLog(fmt, ...)

static NSString * kOpenUDIDSessionCache = nil;
static NSString * const kOpenUDIDKey = @"OpenUDID";
static NSString * const kOpenUDIDSlotKey = @"OpenUDID_slot";
static NSString * const kOpenUDIDBIDKey = @"OpenUDID_bundleid";
static NSString * const kOpenUDIDTSKey = @"OpenUDID_createdTS";
static NSString * const kOpenUDIDOOTSKey = @"OpenUDID_optOutTS";
static NSString * const kOpenUDIDDomain = @"org.OpenUDID";
static NSString * const kOpenUDIDSlotPBPrefix = @"org.OpenUDID.slot.";
static int const kOpenUDIDRedundancySlots = 100;
static KeychainItemWrapper* keychain = nil;

@interface OpenUDID (Private)
+ (void) _setDict:(id)dict forPasteboard:(id)pboard;
+ (NSMutableDictionary*) _getDictFromPasteboard:(id)pboard;
+ (NSString*) _getOpenUDID;
@end

@implementation OpenUDID

// Archive a NSDictionary inside a pasteboard of a given type
// Convenience method to support iOS & Mac OS X
//
+ (void) _setDict:(id)dict forPasteboard:(id)pboard {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR		
    [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:dict] forPasteboardType:kOpenUDIDDomain];
#else
    [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:dict] forType:kOpenUDIDDomain];
#endif
}

// Retrieve an NSDictionary from a pasteboard of a given type
// Convenience method to support iOS & Mac OS X
//
+ (NSMutableDictionary*) _getDictFromPasteboard:(id)pboard {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR	
    id item = [pboard dataForPasteboardType:kOpenUDIDDomain];
#else
	id item = [pboard dataForType:kOpenUDIDDomain];
#endif	
    if (item)
        item = [NSKeyedUnarchiver unarchiveObjectWithData:item];
    
    // return an instance of a MutableDictionary 
    return [NSMutableDictionary dictionaryWithDictionary:(item == nil || [item isKindOfClass:[NSDictionary class]]) ? item : nil];
}

// Private method to create and return the OpenUDID
// Note that the default behavior on iOS is to return the current UDID if the function is not deprecated
// Theoretically, this function is called once ever per application when calling [OpenUDID value] for the first time.
// After that, the caching/pasteboard/redundancy mechanism inside [OpenUDID value] returns a persistent and cross application OpenUDID
//
+ (NSString*) _getOpenUDID {
    
    NSString* _openUDID = nil;
    
    // 2011: One day, this may no longer be allowed in iOS. When that is, just comment this line out.
    // March 25th 2012: this day has come, let's remove this "outlawed" call... 
#if TARGET_OS_IPHONE	
//    if([UIDevice instancesRespondToSelector:@selector(uniqueIdentifier)]){
//        _openUDID = [[UIDevice currentDevice] uniqueIdentifier];
//    }
    
#endif
    
    // Take this opportunity to give the simulator a proper UDID (i.e. nullify UDID and create an OpenUDID)
    //
#if TARGET_IPHONE_SIMULATOR
    _openUDID = nil;
#endif
    
    // Next we try to use an alternative method which uses the host name, process ID, and a time stamp
    // We then hash it with md5 to get 32 bytes, and then add 4 extra random bytes
    // Collision is possible of course, but unlikely and suitable for most industry needs (e.g.. aggregate tracking)
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
    //
    // feel free to suggest better or alternative "UDID" generation code above.
    // NOTE that the goal is NOT to find a better hash method, but rather, find a decentralized (i.e. not web-based)
    // 160 bits / 20 bytes random string generator with the fewest possible collisions.
    // 

    return _openUDID;
}


// Main public method that returns the OpenUDID
// This method will generate and store the OpenUDID if it doesn't exist, typically the first time it is called
// It will return the null udid (forty zeros) if the user has somehow opted this app out (this is subject to 3rd party implementation)
// Otherwise, it will register the current app and return the OpenUDID
//
+ (NSString*) value {
    return [OpenUDID valueWithError:nil];
}
+ (NSString*) valueWithError:(NSError **)error {

    if (kOpenUDIDSessionCache!=nil) {
        if (error!=nil)
            *error = [NSError errorWithDomain:kOpenUDIDDomain
                                         code:kOpenUDIDErrorNone
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"OpenUDID in cache from first call",@"description", nil]];
        return kOpenUDIDSessionCache;
    }

    
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *bundleid = [[NSBundle mainBundle] bundleIdentifier];
    NSString* openUDID = nil;
    NSString* myRedundancySlotPBid = nil;
    NSDate* optedOutDate = nil;
    BOOL optedOut = NO;
    BOOL saveLocalDictToDefaults = NO;
    BOOL isCompromised = NO;
    BOOL isMultiples = NO;
    
    // Do we have a local copy of the OpenUDID dictionary?
    // This local copy contains a copy of the openUDID, myRedundancySlotPBid (and unused in this block, the local bundleid, and the timestamp)
    //
    id localDict = [defaults objectForKey:kOpenUDIDKey];
    if ([localDict isKindOfClass:[NSDictionary class]]) {
        localDict = [NSMutableDictionary dictionaryWithDictionary:localDict]; // we might need to set/overwrite the redundancy slot
        openUDID = [localDict objectForKey:kOpenUDIDKey];
        myRedundancySlotPBid = [localDict objectForKey:kOpenUDIDSlotKey];
        OpenUDIDLog(@"localDict = %@",localDict);
    }
    
    // Here we go through a sequence of slots, each of which being a UIPasteboard created by each participating app
    // The idea behind this is to both multiple and redundant representations of OpenUDIDs, as well as serve as placeholder for potential opt-out
    //
    NSString* availableSlotPBid = nil;
    NSMutableDictionary* frequencyDict = [NSMutableDictionary dictionaryWithCapacity:kOpenUDIDRedundancySlots];
    for (int n=0; n<kOpenUDIDRedundancySlots; n++) {
        NSString* slotPBid = [NSString stringWithFormat:@"%@%d",kOpenUDIDSlotPBPrefix,n];
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
        UIPasteboard* slotPB = [UIPasteboard pasteboardWithName:slotPBid create:NO];
#else
        NSPasteboard* slotPB = [NSPasteboard pasteboardWithName:slotPBid];
#endif
        OpenUDIDLog(@"SlotPB name = %@",slotPBid);
        if (slotPB==nil) {
            // assign availableSlotPBid to be the first one available
            if (availableSlotPBid==nil) availableSlotPBid = slotPBid;
        } else {
            NSDictionary* dict = [OpenUDID _getDictFromPasteboard:slotPB];
            NSString* oudid = [dict objectForKey:kOpenUDIDKey];
            OpenUDIDLog(@"SlotPB dict = %@",dict);
            if (oudid==nil) {
                // availableSlotPBid could inside a non null slot where no oudid can be found
                if (availableSlotPBid==nil) availableSlotPBid = slotPBid;
            } else {
                // increment the frequency of this oudid key
                int count = [[frequencyDict valueForKey:oudid] intValue];
                [frequencyDict setObject:[NSNumber numberWithInt:++count] forKey:oudid];
            }
            // if we have a match with the bundleid, then let's look if the external UIPasteboard representation marks this app as OptedOut
            NSString* bid = [dict objectForKey:kOpenUDIDBIDKey];
            if (bid!=nil && [bid isEqualToString:bundleid]) {
                myRedundancySlotPBid = slotPBid;
                optedOutDate = [dict objectForKey:kOpenUDIDOOTSKey];
                optedOut = optedOutDate!=nil;
            }
        }
    }
    
    // sort the Frequency dict with highest occurence count of the same OpenUDID (redundancy, failsafe)
    // highest is last in the list
    //
    NSArray* arrayOfUDIDs = [frequencyDict keysSortedByValueUsingSelector:@selector(compare:)];
    NSString* mostReliableOpenUDID = (arrayOfUDIDs!=nil && [arrayOfUDIDs count]>0)? [arrayOfUDIDs lastObject] : nil;
    OpenUDIDLog(@"Freq Dict = %@\nMost reliable %@",frequencyDict,mostReliableOpenUDID);
      
    if( keychain == nil )
        keychain = [[KeychainItemWrapper alloc]initWithIdentifier:kOpenUDIDKey accessGroup:nil];
    
    NSString* keyChainUDID = [keychain objectForKey:(id)kSecValueData];
    OpenUDIDLog(@"Keychain UDID = %@", keyChainUDID);
    
    // if openUDID was not retrieved from the local preferences, then let's try to get it from the frequency dictionary above
    //
    if (openUDID==nil) {        
        if (mostReliableOpenUDID==nil) {
            // This is the case where this app instance is likely to be the first one to use OpenUDID on this device.
            // First, check to see if THIS app has created an OpenUDID previously and stored it into the keychain.
            // If not, we create the new OpenUDID, legacy or semi-random (i.e. most certainly unique)
            //
            openUDID = keyChainUDID;
            if( [openUDID length] == 0 )
                openUDID = [OpenUDID _getOpenUDID];
            
        } else {
            // Or we leverage the OpenUDID shared by other apps that have already gone through the process
            // HOWEVER, if the keychain stored UDID is present, favor that value for consistency across 
            // application installs in THIS app and mark the value as multiples (for now)
            // NOTE: In future, we need to come up with a way to handle this case more elegantly... how to sync
            // these values when a new OpenUDID is generated between existing application installs?
            //
            if( [mostReliableOpenUDID isEqualToString:keyChainUDID] && [keyChainUDID length] > 0 )
            {
                // Equal and life is good.
                openUDID = mostReliableOpenUDID;
            }
            else if( [keyChainUDID length] > 0 )
            {
                // Keychain value and stored value are different.  This could occur if this app was originally installed
                // and then removed.  Before this app was reinstalled, a new OpenUDID enabled app created a new value.
                // Now this app is reinstalled.  For consistency in THIS app, deferring to the keychain value.  In future
                // Need to find some way to handle this case more elegantly.
                openUDID = keyChainUDID;
                isMultiples = YES;
            }
            else
            {
                // Don't have a keychain value yet... so this is the first time this app has been installed
                // Defer to the previously saved OpenUDID and store it in the keychain for this app.
                openUDID = mostReliableOpenUDID;
            }
        }
        // then we create a local representation
        //
        if (localDict==nil) { 
            localDict = [NSMutableDictionary dictionaryWithCapacity:4];
            [localDict setObject:openUDID forKey:kOpenUDIDKey];
            [localDict setObject:bundleid forKey:kOpenUDIDBIDKey];
            [localDict setObject:[NSDate date] forKey:kOpenUDIDTSKey];
            if (optedOut) [localDict setObject:optedOutDate forKey:kOpenUDIDTSKey];
            saveLocalDictToDefaults = YES;
        }
    }
    else {
        // Sanity/tampering check
        //
        if (mostReliableOpenUDID!=nil && ![mostReliableOpenUDID isEqualToString:openUDID])
            isCompromised = YES;
    }
    
    // Here we store in the available PB slot, if applicable
    //
    OpenUDIDLog(@"Available Slot %@ Existing Slot %@",availableSlotPBid,myRedundancySlotPBid);
    if (availableSlotPBid!=nil && (myRedundancySlotPBid==nil || [availableSlotPBid isEqualToString:myRedundancySlotPBid])) {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
        UIPasteboard* slotPB = [UIPasteboard pasteboardWithName:availableSlotPBid create:YES];
        [slotPB setPersistent:YES];
#else
        NSPasteboard* slotPB = [NSPasteboard pasteboardWithName:availableSlotPBid];
#endif
        
        // save slotPBid to the defaults, and remember to save later
        //
        if (localDict) {
            [localDict setObject:availableSlotPBid forKey:kOpenUDIDSlotKey];
            saveLocalDictToDefaults = YES;
        }
        
        // Save the local dictionary to the corresponding UIPasteboard slot
        //
        if (openUDID && localDict)
            [OpenUDID _setDict:localDict forPasteboard:slotPB];
    }

    // Save the dictionary locally if applicable
    //
    if (localDict && saveLocalDictToDefaults)
        [defaults setObject:localDict forKey:kOpenUDIDKey];
    
    // Save the OpenUDID to the keychain if needed
    if( [[keychain objectForKey:(id)kSecValueData]length] == 0 )
        [keychain setObject:openUDID forKey:(id)kSecValueData];

    // If the UIPasteboard externa representation marks this app as opted-out, then to respect privacy, we return the ZERO OpenUDID, a sequence of 40 zeros...
    // This is a *new* case that developers have to deal with. Unlikely, statistically low, but still.
    // To circumvent this and maintain good tracking (conversion ratios, etc.), developers are invited to calculate how many of their users have opted-out from the full set of users.
    // This ratio will let them extrapolate convertion ratios more accurately.
    //
    if (optedOut) {
        if (error!=nil) *error = [NSError errorWithDomain:kOpenUDIDDomain
                                                     code:kOpenUDIDErrorOptedOut
                                                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"Application %@ is opted-out from OpenUDID as of %@",bundleid,optedOutDate],@"description", nil]];
            
        kOpenUDIDSessionCache = [[NSString stringWithFormat:@"%040x",0] retain];
        return kOpenUDIDSessionCache;
    }

    // return the well earned openUDID!
    //
    if (error!=nil) {
        if (isCompromised)
            *error = [NSError errorWithDomain:kOpenUDIDDomain
                                         code:kOpenUDIDErrorCompromised
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"Found a discrepancy between stored OpenUDID (reliable) and redundant copies; one of the apps on the device is most likely corrupting the OpenUDID protocol",@"description", nil]];
        else if( isMultiples )
            *error = [NSError errorWithDomain:kOpenUDIDDomain
                                         code:kOpenUDIDErrorMultiple
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"Found multiple OpenUDID values (keychain vs cross-application stores). This occurs when all OpenUDID-enabled apps are removed, a new one is installed, and then a previous app is reinstalled",@"description", nil]];
        else
            *error = [NSError errorWithDomain:kOpenUDIDDomain
                                         code:kOpenUDIDErrorNone
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"OpenUDID succesfully retrieved",@"description", nil]];
    }
    kOpenUDIDSessionCache = [openUDID retain];
    return kOpenUDIDSessionCache;
}

@end

#pragma mark
#pragma mark Apple KeychainItemWrapper implementation

/*
 File: KeychainItemWrapper.m 
 Abstract: 
 Objective-C wrapper for accessing a single keychain item.
 
 Version: 1.2 
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple 
 Inc. ("Apple") in consideration of your agreement to the following 
 terms, and your use, installation, modification or redistribution of 
 this Apple software constitutes acceptance of these terms.  If you do 
 not agree with these terms, please do not use, install, modify or 
 redistribute this Apple software. 
 
 In consideration of your agreement to abide by the following terms, and 
 subject to these terms, Apple grants you a personal, non-exclusive 
 license, under Apple's copyrights in this original Apple software (the 
 "Apple Software"), to use, reproduce, modify and redistribute the Apple 
 Software, with or without modifications, in source and/or binary forms; 
 provided that if you redistribute the Apple Software in its entirety and 
 without modifications, you must retain this notice and the following 
 text and disclaimers in all such redistributions of the Apple Software. 
 Neither the name, trademarks, service marks or logos of Apple Inc. may 
 be used to endorse or promote products derived from the Apple Software 
 without specific prior written permission from Apple.  Except as 
 expressly stated in this notice, no other rights or licenses, express or 
 implied, are granted by Apple herein, including but not limited to any 
 patent rights that may be infringed by your derivative works or by other 
 works in which the Apple Software may be incorporated. 
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE 
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION 
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS 
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND 
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS. 
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL 
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, 
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED 
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE), 
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE 
 POSSIBILITY OF SUCH DAMAGE. 
 
 Copyright (C) 2010 Apple Inc. All Rights Reserved. 
 
 */ 

#import <Security/Security.h>

/*
 
 These are the default constants and their respective types,
 available for the kSecClassGenericPassword Keychain Item class:
 
 kSecAttrAccessGroup         -       CFStringRef
 kSecAttrCreationDate        -       CFDateRef
 kSecAttrModificationDate    -       CFDateRef
 kSecAttrDescription         -       CFStringRef
 kSecAttrComment             -       CFStringRef
 kSecAttrCreator             -       CFNumberRef
 kSecAttrType                -       CFNumberRef
 kSecAttrLabel               -       CFStringRef
 kSecAttrIsInvisible         -       CFBooleanRef
 kSecAttrIsNegative          -       CFBooleanRef
 kSecAttrAccount             -       CFStringRef
 kSecAttrService             -       CFStringRef
 kSecAttrGeneric             -       CFDataRef
 
 See the header file Security/SecItem.h for more details.
 
 */

@interface KeychainItemWrapper (PrivateMethods)
/*
 The decision behind the following two methods (secItemFormatToDictionary and dictionaryToSecItemFormat) was
 to encapsulate the transition between what the detail view controller was expecting (NSString *) and what the
 Keychain API expects as a validly constructed container class.
 */
- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert;
- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert;

// Updates the item in the keychain, or adds it if it doesn't exist.
- (void)writeToKeychain;

@end

@implementation KeychainItemWrapper

@synthesize keychainItemData, genericPasswordQuery;

- (id)initWithIdentifier: (NSString *)identifier accessGroup:(NSString *) accessGroup;
{
    if (self = [super init])
    {
        // Begin Keychain search setup. The genericPasswordQuery leverages the special user
        // defined attribute kSecAttrGeneric to distinguish itself between other generic Keychain
        // items which may be included by the same application.
        genericPasswordQuery = [[NSMutableDictionary alloc] init];
        
        [genericPasswordQuery setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
        [genericPasswordQuery setObject:identifier forKey:(id)kSecAttrGeneric];
        
        // The keychain access group attribute determines if this item can be shared
        // amongst multiple apps whose code signing entitlements contain the same keychain access group.
        if (accessGroup != nil)
        {
#if TARGET_IPHONE_SIMULATOR
            // Ignore the access group if running on the iPhone simulator.
            // 
            // Apps that are built for the simulator aren't signed, so there's no keychain access group
            // for the simulator to check. This means that all apps can see all keychain items when run
            // on the simulator.
            //
            // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
            // simulator will return -25243 (errSecNoAccessForItem).
#else           
            [genericPasswordQuery setObject:accessGroup forKey:(id)kSecAttrAccessGroup];
#endif
        }
        
        // Use the proper search constants, return only the attributes of the first match.
        [genericPasswordQuery setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];
        [genericPasswordQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
        
        NSDictionary *tempQuery = [NSDictionary dictionaryWithDictionary:genericPasswordQuery];
        
        NSMutableDictionary *outDictionary = nil;
        
        if (! SecItemCopyMatching((CFDictionaryRef)tempQuery, (CFTypeRef *)&outDictionary) == noErr)
        {
            // Stick these default values into keychain item if nothing found.
            [self resetKeychainItem];
            
            // Add the generic attribute and the keychain access group.
            [keychainItemData setObject:identifier forKey:(id)kSecAttrGeneric];
            if (accessGroup != nil)
            {
#if TARGET_IPHONE_SIMULATOR
                // Ignore the access group if running on the iPhone simulator.
                // 
                // Apps that are built for the simulator aren't signed, so there's no keychain access group
                // for the simulator to check. This means that all apps can see all keychain items when run
                // on the simulator.
                //
                // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
                // simulator will return -25243 (errSecNoAccessForItem).
#else           
                [keychainItemData setObject:accessGroup forKey:(id)kSecAttrAccessGroup];
#endif
            }
        }
        else
        {
            // load the saved data from Keychain.
            self.keychainItemData = [self secItemFormatToDictionary:outDictionary];
        }
        
        [outDictionary release];
    }
    
    return self;
}

- (void)dealloc
{
    [keychainItemData release];
    [genericPasswordQuery release];
    
    [super dealloc];
}

- (void)setObject:(id)inObject forKey:(id)key 
{
    if (inObject == nil) return;
    id currentObject = [keychainItemData objectForKey:key];
    if (![currentObject isEqual:inObject])
    {
        [keychainItemData setObject:inObject forKey:key];
        [self writeToKeychain];
    }
}

- (id)objectForKey:(id)key
{
    return [keychainItemData objectForKey:key];
}

- (void)resetKeychainItem
{
    OSStatus junk = noErr;
    if (!keychainItemData) 
    {
        self.keychainItemData = [[NSMutableDictionary alloc] init];
    }
    else if (keychainItemData)
    {
        NSMutableDictionary *tempDictionary = [self dictionaryToSecItemFormat:keychainItemData];
        junk = SecItemDelete((CFDictionaryRef)tempDictionary);
        NSAssert( junk == noErr || junk == errSecItemNotFound, @"Problem deleting current dictionary." );
    }
    
    // Default attributes for keychain item.
    [keychainItemData setObject:@"" forKey:(id)kSecAttrAccount];
    [keychainItemData setObject:@"" forKey:(id)kSecAttrLabel];
    [keychainItemData setObject:@"" forKey:(id)kSecAttrDescription];
    
    // Default data for keychain item.
    [keychainItemData setObject:@"" forKey:(id)kSecValueData];
}

- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert
{
    // The assumption is that this method will be called with a properly populated dictionary
    // containing all the right key/value pairs for a SecItem.
    
    // Create a dictionary to return populated with the attributes and data.
    NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionaryToConvert];
    
    // Add the Generic Password keychain item class attribute.
    [returnDictionary setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
    
    // Convert the NSString to NSData to meet the requirements for the value type kSecValueData.
    // This is where to store sensitive data that should be encrypted.
    NSString *passwordString = [dictionaryToConvert objectForKey:(id)kSecValueData];
    [returnDictionary setObject:[passwordString dataUsingEncoding:NSUTF8StringEncoding] forKey:(id)kSecValueData];
    
    return returnDictionary;
}

- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert
{
    // The assumption is that this method will be called with a properly populated dictionary
    // containing all the right key/value pairs for the UI element.
    
    // Create a dictionary to return populated with the attributes and data.
    NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionaryToConvert];
    
    // Add the proper search key and class attribute.
    [returnDictionary setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    [returnDictionary setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
    
    // Acquire the password data from the attributes.
    NSData *passwordData = NULL;
    if (SecItemCopyMatching((CFDictionaryRef)returnDictionary, (CFTypeRef *)&passwordData) == noErr)
    {
        // Remove the search, class, and identifier key/value, we don't need them anymore.
        [returnDictionary removeObjectForKey:(id)kSecReturnData];
        
        // Add the password to the dictionary, converting from NSData to NSString.
        NSString *password = [[[NSString alloc] initWithBytes:[passwordData bytes] length:[passwordData length] 
                                                     encoding:NSUTF8StringEncoding] autorelease];
        [returnDictionary setObject:password forKey:(id)kSecValueData];
    }
    else
    {
        // Don't do anything if nothing is found.
        NSAssert(NO, @"Serious error, no matching item found in the keychain.\n");
    }
    
    [passwordData release];
    
    return returnDictionary;
}

- (void)writeToKeychain
{
    NSDictionary *attributes = NULL;
    NSMutableDictionary *updateItem = NULL;
    OSStatus result;
    
    if (SecItemCopyMatching((CFDictionaryRef)genericPasswordQuery, (CFTypeRef *)&attributes) == noErr)
    {
        // First we need the attributes from the Keychain.
        updateItem = [NSMutableDictionary dictionaryWithDictionary:attributes];
        // Second we need to add the appropriate search key/values.
        [updateItem setObject:[genericPasswordQuery objectForKey:(id)kSecClass] forKey:(id)kSecClass];
        
        // Lastly, we need to set up the updated attribute list being careful to remove the class.
        NSMutableDictionary *tempCheck = [self dictionaryToSecItemFormat:keychainItemData];
        [tempCheck removeObjectForKey:(id)kSecClass];
        
#if TARGET_IPHONE_SIMULATOR
        // Remove the access group if running on the iPhone simulator.
        // 
        // Apps that are built for the simulator aren't signed, so there's no keychain access group
        // for the simulator to check. This means that all apps can see all keychain items when run
        // on the simulator.
        //
        // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
        // simulator will return -25243 (errSecNoAccessForItem).
        //
        // The access group attribute will be included in items returned by SecItemCopyMatching,
        // which is why we need to remove it before updating the item.
        [tempCheck removeObjectForKey:(id)kSecAttrAccessGroup];
#endif
        
        // An implicit assumption is that you can only update a single item at a time.
        
        result = SecItemUpdate((CFDictionaryRef)updateItem, (CFDictionaryRef)tempCheck);
        NSAssert( result == noErr, @"Couldn't update the Keychain Item." );
    }
    else
    {
        // No previous item found; add the new one.
        result = SecItemAdd((CFDictionaryRef)[self dictionaryToSecItemFormat:keychainItemData], NULL);
        NSAssert( result == noErr, @"Couldn't add the Keychain Item." );
    }
}

@end

#pragma mark -


