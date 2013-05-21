//
//  XcodeColors.m
//  XcodeColors
//
//  Created by Uncle MiF on 9/13/10.
//  Copyright 2010 Deep IT. All rights reserved.
//

#import "XcodeColors.h"
#import <objc/runtime.h>

#define XCODE_COLORS "XcodeColors"

// How to apply color formatting to your log statements:
// Use ANSI color escapes.
// Supports only the "m" code.
// Supports code 0 (reset), 1 (bold), 30-37 (fg color), 40-47 (bg color), 300 (three rgb params, fg color), 400 (three rgb params, bg color)
// 
//
// Feel free to copy the define statements below into your code.
// <COPY ME>

#define XCODE_COLORS_ESCAPE @"\033["

// </COPY ME>

static IMP IMP_NSTextStorage_fixAttributesInRange = nil;
static bool XcodeColors_intensityStateFlag = false;


@implementation XcodeColors_NSTextStorage

static NSUInteger ParseEscapeSequence(NSString *component, NSMutableDictionary *attrs)
{
	// An ANSI color code has the form:
	// \033[k;k...m
	// There may be zero or more parameters.
	NSRange rangeOfCodeEnd = [component rangeOfString:@"m"];

	if (rangeOfCodeEnd.location == NSNotFound) // not a valid color escape code, let's not do anything with it
		return 0;
	
	NSString *params = [component substringToIndex:rangeOfCodeEnd.location];
	
	// we only support numeric codes
	if ([params rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789;"] invertedSet]].location != NSNotFound)
		return 0;
	
	NSArray *paramList = [params componentsSeparatedByString:@";"];
	
	const CGFloat ansiReds[]   = { 0.0, 194.0, 37.0, 173.0, 73.0, 211.0, 51.0, 203.0, 129.0, 252.0, 49.0, 234.0, 88.0, 249.0, 20.0, 233.0 },
				  ansiGreens[] = { 0.0, 54.0, 188.0, 173.0, 46.0, 56.0, 187.0, 204.0, 131.0, 57.0, 231.0, 236.0, 51.0, 53.0, 240.0, 235.0 },
				  ansiBlues[]  = { 0.0, 33.0, 36.0, 39.0, 255.0, 211.0, 200.0, 205.0, 131.0, 31.0, 34.0, 35.0, 255.0, 248.0, 240.0, 235.0 };
	
	for (NSUInteger i = 0; i < paramList.count; ++i) { // May need to skip params, can't use for..in
		NSUInteger param = [paramList[i] integerValue];
		
		switch (param) {
			case 0: // reset
				[attrs removeObjectsForKeys:@[NSForegroundColorAttributeName, NSBackgroundColorAttributeName]];
				XcodeColors_intensityStateFlag = false;
				break;
			case 1: // bold
				XcodeColors_intensityStateFlag = true;
				break;
			case 30: case 31: case 32: case 33: case 34: case 35: case 36: case 37:
				attrs[NSForegroundColorAttributeName] = [NSColor
					colorWithCalibratedRed:ansiReds[param - 30 + (!!XcodeColors_intensityStateFlag * 8)] / 255.0
					green:ansiGreens[param - 30 + (!!XcodeColors_intensityStateFlag * 8)] / 255.0
					blue:ansiBlues[param - 30 + (!!XcodeColors_intensityStateFlag * 8)] / 255.0
					alpha:1.0];
				break;
			case 40: case 41: case 42: case 43: case 44: case 45: case 46: case 47:
				attrs[NSBackgroundColorAttributeName] = [NSColor
					colorWithCalibratedRed:ansiReds[param - 40 + (!!XcodeColors_intensityStateFlag * 8)] / 255.0
					green:ansiGreens[param - 40 + (!!XcodeColors_intensityStateFlag * 8)] / 255.0
					blue:ansiBlues[param - 40 + (!!XcodeColors_intensityStateFlag * 8)] / 255.0
					alpha:1.0];
				break;
			case 300:
				if ((i + 3) >= paramList.count)
					return 0;
				attrs[NSForegroundColorAttributeName] = [NSColor
					colorWithCalibratedRed:[paramList[++i] integerValue] / 255.0
					green:[paramList[++i] integerValue] / 255.0
					blue:[paramList[++i] integerValue] / 255.0
					alpha:1.0];
				break;
			case 400:
				if ((i + 3) >= paramList.count)
					return 0;
				attrs[NSBackgroundColorAttributeName] = [NSColor
					colorWithCalibratedRed:[paramList[++i] unsignedIntegerValue] / 255.0
					green:[paramList[++i] unsignedIntegerValue] / 255.0
					blue:[paramList[++i] unsignedIntegerValue] / 255.0
					alpha:1.0];
				break;
			default:
				break; // ignore unknown codes
		}
	}
	return rangeOfCodeEnd.location + 1;
}

static void ApplyANSIColors(NSTextStorage *textStorage, NSRange textStorageRange, NSString *escapeSeq)
{
	NSRange range = [[textStorage string] rangeOfString:escapeSeq options:0 range:textStorageRange];
	if (range.location == NSNotFound) // No escape sequence(s) in the string.
		return;
	
	// Architecture:
	// 
	// We're going to split the string into components separated by the given escape sequence.
	// Then we're going to loop over the components, looking for color codes at the beginning of each component.
	// 
	// The attributes are applied to the entire range of the component, and then we move onto the next component.
	// 
	// At the very end, we go back and apply "invisible" attributes (zero font, and clear text)
	// to the escape and color sequences.
	NSString *affectedString = [[textStorage string] substringWithRange:textStorageRange];
	
	// Split the string into components separated by the given escape sequence.
	NSArray *components = [affectedString componentsSeparatedByString:escapeSeq];
	NSRange componentRange = { textStorageRange.location, 0 };
	BOOL firstPass = YES;
	NSMutableArray *seqRanges = @[].mutableCopy;
	NSMutableDictionary *attrs = @{}.mutableCopy;
	
	for (NSString *component in components)
	{
		if (firstPass)
		{
			// The first component in the array won't need processing.
			// If there was an escape sequence at the very beginning of the string,
			// then the first component in the array will be an empty string.
			// Otherwise the first component is everything before the first escape sequence.
		}
		else
		{
			// componentSeqRange : Range of escape sequence within component, e.g. "fg124,12,12;"
			NSUInteger seqLen = ParseEscapeSequence(component, attrs);
			
			if (seqLen) {
				[seqRanges addObject:[NSValue valueWithRange:(NSRange){
					.location = componentRange.location - escapeSeq.length,
					.length = seqLen + escapeSeq.length
				}]];
			}
		}
		
		componentRange.length = component.length;
		[textStorage addAttributes:attrs range:componentRange];
		componentRange.location += componentRange.length + escapeSeq.length;
		firstPass = NO;
		
	} // END: for (NSString *component in components)
	
	// Now loop over all the discovered sequences, and apply "invisible" attributes to them.
	NSDictionary *clearAttrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:0.001], NSForegroundColorAttributeName: [NSColor clearColor] };
	
	for (NSValue *seqRangeValue in seqRanges)
	{
		NSRange seqRange = [seqRangeValue rangeValue];
		[textStorage addAttributes:clearAttrs range:seqRange];
	}
}

- (void)fixAttributesInRange:(NSRange)aRange
{
	// This method "overrides" the method within NSTextStorage.
	
	// First we invoke the actual NSTextStorage method.
	// This allows it to do any normal processing.
	
	IMP_NSTextStorage_fixAttributesInRange(self, _cmd, aRange);
	
	// Then we scan for our special escape sequences, and apply desired color attributes.
	
	char *xcode_colors = getenv(XCODE_COLORS);
	if (xcode_colors && (strcmp(xcode_colors, "YES") == 0))
		ApplyANSIColors(self, aRange, XCODE_COLORS_ESCAPE);
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation XcodeColors

IMP ReplaceInstanceMethod(Class sourceClass, SEL sourceSel, Class destinationClass, SEL destinationSel)
{
	if (!sourceSel || !sourceClass || !destinationClass)
	{
		NSLog(@"XcodeColors: Missing parameter to ReplaceInstanceMethod");
		return nil;
	}
	
	if (!destinationSel)
		destinationSel = sourceSel;
	
	Method sourceMethod = class_getInstanceMethod(sourceClass, sourceSel);
	if (!sourceMethod)
	{
		NSLog(@"XcodeColors: Unable to get sourceMethod");
		return nil;
	}
	
	IMP prevImplementation = method_getImplementation(sourceMethod);
	
	Method destinationMethod = class_getInstanceMethod(destinationClass, destinationSel);
	if (!destinationMethod)
	{
		NSLog(@"XcodeColors: Unable to get destinationMethod");
		return nil;
	}
	
	IMP newImplementation = method_getImplementation(destinationMethod);
	if (!newImplementation)
	{
		NSLog(@"XcodeColors: Unable to get newImplementation");
		return nil;
	}
	
	method_setImplementation(sourceMethod, newImplementation);
	
	return prevImplementation;
}

+ (void)load
{
	NSLog(@"XcodeColors: %@ (v10.1)", NSStringFromSelector(_cmd));
	
	char *xcode_colors = getenv(XCODE_COLORS);
	if (xcode_colors && (strcmp(xcode_colors, "YES") != 0))
		return;
	
	IMP_NSTextStorage_fixAttributesInRange =
	    ReplaceInstanceMethod([NSTextStorage class], @selector(fixAttributesInRange:),
							  [XcodeColors_NSTextStorage class], @selector(fixAttributesInRange:));
	
	setenv(XCODE_COLORS, "YES", 0);
}

+ (void)pluginDidLoad:(id)xcodeDirectCompatibility
{
	NSLog(@"XcodeColors: %@", NSStringFromSelector(_cmd));
}

- (void)registerLaunchSystemDescriptions
{
	NSLog(@"XcodeColors: %@", NSStringFromSelector(_cmd));
}

@end
