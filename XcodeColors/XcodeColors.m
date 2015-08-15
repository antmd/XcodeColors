//
//  XcodeColors.m
//  XcodeColors
//
//  Created by Uncle MiF on 9/13/10.
//  Copyright 2010 Deep IT. All rights reserved.
//

#import "XcodeColors.h"
#import "JRSwizzle.h"

#define XCODE_COLORS "XcodeColors"
#define SOLARIZED_DARK 1

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


@implementation NSTextStorage (XcodeColors)

static NSColor *colorForCode(NSUInteger code, BOOL bright)
{
        assert(code < 8);
        const static CGFloat
#if SOLARIZED_LIGHT
        ansiReds[] =   { 7.0, 220.0, 133.0, 181.0, 38.0, 211.0, 42.0, 238.0, /* BRIGHT */ 0.0, 203.0, 88.0, 101.0, 131.0, 108.0, 147.0, 253.0 },
        ansiGreens[] = { 54.0, 50.0, 153.0, 137.0, 139.0, 54.0, 161.0, 232.0, /* BRIGHT */ 43.0, 75.0, 110.0, 123.0, 148.0, 113.0, 161.0, 246.0 },
        ansiBlues[] =  { 66.0, 47.0, 0.0, 0.0, 210.0, 130.0, 152.0, 213.0, /* BRIGHT */ 54.0, 22.0, 117.0, 131.0, 150.0, 196.0, 161.0, 227.0 };
#elif SOLARIZED_DARK
        ansiReds[] =   { 238.0, 220.0, 133.0, 181.0, 38.0, 211.0, 42.0, 7.0, /* BRIGHT */ 253.0, 203.0, 147.0, 131.0, 101.0, 108.0, 88.0, 0.0},
        ansiGreens[] = { 232.0, 50.0, 153.0, 137.0, 139.0, 54.0, 161.0, 54.0, /* BRIGHT */ 246.0, 75.0, 161.0, 148.0, 123.0, 113.0, 110.0, 43.0},
        ansiBlues[] =  { 213.0, 47.0, 0.0, 0.0, 210.0, 130.0, 152.0, 66.0, /* BRIGHT */ 227.0, 22.0, 161.0, 150.0, 131.0, 196.0, 117.0, 54.0};
#else
        // Terminal.app default colours
        ansiReds[]   = { 0.0, 194.0, 37.0, 173.0, 73.0, 211.0, 51.0, 203.0, /* BRIGHT */ 129.0, 252.0, 49.0, 234.0, 88.0, 249.0, 20.0, 233.0 },
        ansiGreens[] = { 0.0, 54.0, 188.0, 173.0, 46.0, 56.0, 187.0, 204.0, /* BRIGHT */ 131.0, 57.0, 231.0, 236.0, 51.0, 53.0, 240.0, 235.0 },
        ansiBlues[]  = { 0.0, 33.0, 36.0, 39.0, 255.0, 211.0, 200.0, 205.0, /* BRIGHT */ 131.0, 31.0, 34.0, 35.0, 255.0, 248.0, 240.0, 235.0 };
#endif
        


        static NSArray* sColors = nil;
        
        if (!sColors) {
                sColors = [NSMutableArray arrayWithCapacity:16];
                for (size_t i=0; i < 16; ++i) {
                        [(NSMutableArray*)sColors addObject:[NSColor
                                                             colorWithCalibratedRed:ansiReds[i] / 255.0
                                                             green:ansiGreens[i] / 255.0
                                                             blue:ansiBlues[i] / 255.0
                                                             alpha:1.0]];
                }
                
        }
        
        return sColors[code + (bright?8:0)];
}

static inline NSCharacterSet *disallowedCharacters()
{
        static NSCharacterSet *sDisallowedCharacters = nil;
        if (!sDisallowedCharacters) {
                sDisallowedCharacters = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789;"] invertedSet];
        }
        return sDisallowedCharacters;
}

static NSUInteger ParseEscapeSequence(NSString *component, NSMutableDictionary *attrs)
{
	// An ANSI color code has the form:
	// \033[k;k...m
	// There may be zero or more parameters.
	NSRange rangeOfCodeEnd = [component rangeOfString:@"m"];

        if (rangeOfCodeEnd.location == NSNotFound) { // not a valid color escape code, let's not do anything with it
		return 0;
        }
	
	NSString *params = [component substringToIndex:rangeOfCodeEnd.location];
	
	// we only support numeric codes
        if ([params rangeOfCharacterFromSet:disallowedCharacters()].location != NSNotFound) {
		return 0;
        }
	
	NSArray *paramList = [params componentsSeparatedByString:@";"];
	
        NSUInteger foregroundColorCode = NSNotFound;
        NSUInteger backgroundColorCode = NSNotFound;
	
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
			case 30: case 31: case 32: case 33: case 34: case 35: case 36: case 37: /* ANSI foreground colour */
                                foregroundColorCode = param - 30;
				break;
			case 40: case 41: case 42: case 43: case 44: case 45: case 46: case 47: /* ANSI background colour */
                                backgroundColorCode = param - 40;
				break;
                                
                        case 300: /* Arbitrary foreground colour: must be followed by three params specfiying Red, Green, Blue components */
                                
				if ((i + 3) >= paramList.count)
					return 0;
                                foregroundColorCode = NSNotFound;
				attrs[NSForegroundColorAttributeName] = [NSColor
					colorWithCalibratedRed:((CGFloat)[paramList[++i] integerValue]) / 255.0
					green:((CGFloat)[paramList[++i] integerValue]) / 255.0
					blue:((CGFloat)[paramList[++i] integerValue]) / 255.0
					alpha:1.0];
				break;
			case 400: /* Arbitrary background colour: must be followed by three params specfiying Red, Green, Blue components */
				if ((i + 3) >= paramList.count)
					return 0;
                                backgroundColorCode = NSNotFound;
				attrs[NSBackgroundColorAttributeName] = [NSColor
					colorWithCalibratedRed:(CGFloat)[paramList[++i] integerValue] / 255.0
					green:(CGFloat)[paramList[++i] integerValue] / 255.0
					blue:(CGFloat)[paramList[++i] integerValue] / 255.0
					alpha:1.0];
				break;
			default:
				break; // ignore unknown codes
		}
	}
        if (foregroundColorCode != NSNotFound) {
                attrs[NSForegroundColorAttributeName] = colorForCode(foregroundColorCode, XcodeColors_intensityStateFlag);
        }
        if (backgroundColorCode != NSNotFound) {
                attrs[NSBackgroundColorAttributeName] = colorForCode(backgroundColorCode, XcodeColors_intensityStateFlag);
        }
	return rangeOfCodeEnd.location + 1;
}

static void ApplyANSIColors(NSTextStorage *textStorage, NSRange textStorageRange, NSString *escapeSeq)
{
        static NSDictionary *sClearAttrs = nil;
	NSRange range = [[textStorage string] rangeOfString:escapeSeq options:0 range:textStorageRange];
        if (range.location == NSNotFound) { // No escape sequence(s) in the string.
		return;
        }
	
        if (!sClearAttrs) {
                sClearAttrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:0.001], NSForegroundColorAttributeName: [NSColor clearColor] };
        }
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
		if (firstPass) {
			// The first component in the array won't need processing.
			// If there was an escape sequence at the very beginning of the string,
			// then the first component in the array will be an empty string.
			// Otherwise the first component is everything before the first escape sequence.
		}
		else {
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
	
	for (NSValue *seqRangeValue in seqRanges) {
		NSRange seqRange = [seqRangeValue rangeValue];
		[textStorage addAttributes:sClearAttrs range:seqRange];
	}
}

- (void)xc_fixAttributesInRange:(NSRange)aRange
{
        static Class sIDEConsoleTextViewClass = nil;
        if (!sIDEConsoleTextViewClass) {
                sIDEConsoleTextViewClass = NSClassFromString(@"IDEConsoleTextView");
        }
        // This method "overrides" the method within NSTextStorage.
        
        // First we invoke the actual NSTextStorage method.
        // This allows it to do any normal processing.
        
        // Swizzling makes this look like a recursive call but it's not -- it calls the original!
        [self xc_fixAttributesInRange:aRange];
        
        // Then we scan for our special escape sequences, and apply desired color attributes.
        
        if ([self layoutManagers].count
            && [[self.layoutManagers[0] delegate] isKindOfClass:sIDEConsoleTextViewClass]
            && aRange.length < 1E10) {
                char *xcode_colors = getenv(XCODE_COLORS);
                if (xcode_colors && (strcmp(xcode_colors, "YES") == 0))
                        ApplyANSIColors(self, aRange, XCODE_COLORS_ESCAPE);
        }
}


@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation XcodeColors


+ (void)load
{
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
                /*
                char *xcode_colors = getenv(XCODE_COLORS);
                if (xcode_colors && (strcmp(xcode_colors, "YES") != 0))
                        return;
                 */
                
                SEL origSel = @selector(fixAttributesInRange:);
                SEL altSel = @selector(xc_fixAttributesInRange:);
                NSError *error = nil;
                
                if (![NSTextStorage jr_swizzleMethod:origSel withMethod:altSel error:&error]) {
                        NSLog(@"XcodeColors: Error swizzling methods: %@", error);
                        return;
                }
                
                setenv(XCODE_COLORS, "YES", 0);
        });
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
