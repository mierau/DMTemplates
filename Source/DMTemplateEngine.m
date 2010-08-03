
// DMTemplateEngine.m
// by Dustin Mierau
// Cared for under the MIT license.

#import "DMTemplateEngine.h"

typedef enum {
	DMTemplateValueTagType = 1,
	DMTemplateLogTagType,
	DMTemplateIfTagType,
	DMTemplateElseIfTagType,
	DMTemplateElseTagType,
	DMTemplateEndIfTagType,
	DMTemplateForEachTagType,
	DMTemplateEndForEachTagType
}
DMTemplateTagType;

typedef enum {
	DMTemplateIfBlockType = 1,
	DMTemplateForEachBlockType
}
DMTemplateBlockType;

#pragma mark -

@interface DMTemplateCondition : NSObject
@property (nonatomic, readonly) BOOL isSolved;
@property (nonatomic, assign) BOOL result;
+ (id)condition;
@end

#pragma mark -

@interface DMTemplateTagInfo : NSObject
@property (nonatomic, assign) DMTemplateTagType type;
@property (nonatomic, retain) NSMutableArray* modifiers;
@property (nonatomic, retain) NSString* content;
+ (id)tagInfo;
@end

#pragma mark -

@interface DMTemplateEngine ()
@property (nonatomic, assign) id object;
@property (nonatomic, assign) NSMutableArray* conditionStack;
@property (nonatomic, retain) NSMutableDictionary* modifiers;
@property (nonatomic, assign) NSScanner* scanner;
@property (nonatomic, assign) NSMutableString* renderedTemplate;
@property (nonatomic, readonly) DMTemplateCondition* currentCondition;
@property (nonatomic, readonly) BOOL hasCondition;
@property (nonatomic, readonly) BOOL overallCondition;
- (void)_build;
- (NSArray*)_evaluateForeachStatement:(NSString*)tag;
- (BOOL)_evaluateConditionStatement:(NSString*)tag;
- (NSString*)_parseStatementContent:(NSString*)tag;
- (NSString*)_scanBlockOfType:(DMTemplateBlockType)inType returnContent:(BOOL)inReturnContent;
- (BOOL)_scanSingleNewline;
- (void)_pushCondition:(DMTemplateCondition*)inCondition;
- (void)_popCondition;
- (DMTemplateTagInfo*)_analyzeTagContent:(NSString*)content;
- (DMTemplateTagType)_determineTemplateTagType:(NSString*)tag;
@end

#pragma mark -

@interface DMTemplateEngine (Strings)
+ (NSString*)_stringByEscapingXMLEntities:(NSString*)string;
+ (NSString*)_stringWithReadableByteSize:(unsigned long long)bytes;
+ (NSString*)_stringByAddingPercentEscapes:(NSString*)string;
+ (NSString*)_stringByRemovingCharactersFromSet:(NSCharacterSet*)set string:(NSString*)string;
+ (NSString*)_stringByTrimmingWhitespace:(NSString*)string;
+ (void)_removeCharactersInSet:(NSCharacterSet*)set string:(NSMutableString*)string;
@end

#pragma mark -

@implementation DMTemplateEngine

@synthesize template;
@synthesize object;
@synthesize conditionStack;
@synthesize scanner;
@synthesize renderedTemplate;
@synthesize modifiers;
@synthesize beginProcessorMarker;
@synthesize endProcessorMarker;

#pragma mark -

+ (id)engine {
	return [[[self alloc] init] autorelease];
}

+ (id)engineWithTemplate:(NSString*)template {
	DMTemplateEngine* engine = [self engine];
	engine.template = template;
	return engine;
}

#pragma mark -

- (id)init {
	self = [super init];
	if(self == nil)
		return nil;
	
	// Set default processor markers.
	self.beginProcessorMarker = @"<?";
	self.endProcessorMarker = @"/>";
	
	// Create modifier storage.
	self.modifiers = [NSMutableDictionary dictionary];
	
	// Register URL encode modifier.
	[self addModifier:'u' block:^(NSString* value) {
		return [DMTemplateEngine _stringByAddingPercentEscapes:value];
	}];
	
	// Reguster readable byte size modifier.
	[self addModifier:'b' block:^(NSString* value) {
		return [DMTemplateEngine _stringWithReadableByteSize:[value longLongValue]];
	}];
	
	// Register XML/HTML escape modifier.
	[self addModifier:'e' block:^(NSString* value) {
		return [DMTemplateEngine _stringByEscapingXMLEntities:value];
	}];
	
	return self;
}

- (void)dealloc {
	self.template = nil;
	self.object = nil;
	self.conditionStack = nil;
	self.scanner = nil;
	self.renderedTemplate = nil;
	self.modifiers = nil;
	self.beginProcessorMarker = nil;
	self.endProcessorMarker = nil;
	
	[super dealloc];
}

#pragma mark -
#pragma mark Properties

- (BOOL)hasCondition {
	return ([self.conditionStack count] > 0);
}

- (BOOL)overallCondition {
	// The overall condition is false if a single condition on the stack is false.
	for(DMTemplateCondition* condition in self.conditionStack) {
		if(!condition.result)
			return NO;
	}
	
	return YES;
}

- (DMTemplateCondition*)currentCondition {
	if(self.hasCondition)
		return [self.conditionStack lastObject];
	
	return nil;
}

#pragma mark -
#pragma mark Modifiers

- (void)addModifier:(unichar)modifier block:(NSString*(^)(NSString*))block {
	[self.modifiers setObject:[[block copy] autorelease] forKey:[NSString stringWithCharacters:&modifier length:1]];
}

- (void)removeModifier:(unichar)modifier {
	[self.modifiers removeObjectForKey:[NSString stringWithCharacters:&modifier length:1]];
}

- (void)removeAllModifiers {
	[self.modifiers removeAllObjects];
}

#pragma mark -
#pragma mark Render

- (NSString*)renderAgainst:(id)obj {
	if(self.template == nil)
		return nil;
	
	self.object = obj;
	self.conditionStack = [NSMutableArray array];
	self.renderedTemplate = [NSMutableString string];
	
	// Setup string scanner. Make sure we 
	// skip no characters.
	self.scanner = [NSScanner scannerWithString:self.template];
	[self.scanner setCharactersToBeSkipped:nil];
	
	@try {
		[self _build];
	}
	@catch(id exception) {
		self.renderedTemplate = nil;
	}
	@finally {
		self.object = nil;
		self.conditionStack = nil;
		self.scanner = nil;
	}
	
	return self.renderedTemplate;
}

- (void)_build {
	NSString* startDelimeter = self.beginProcessorMarker;
	NSString* endDelimeter = self.endProcessorMarker;

	while(![self.scanner isAtEnd]) {
		NSAutoreleasePool* memoryPool = nil;
		
		@try {
			// Start a new autorelease pool
			memoryPool = [[NSAutoreleasePool alloc] init];
			
			NSString* tagContent = nil;
			NSString* scannedText = nil;
			BOOL skipContent = !self.overallCondition;

			// Scan contents up to the first start delimeter we can find
			if([self.scanner scanUpToString:startDelimeter intoString:(skipContent ? nil : &scannedText)]) {
				// Append scanned content to result if we are not skipping this content
				if(!skipContent)
					[self.renderedTemplate appendString:scannedText];
			}

			// Scan past start delimeter if possible
			if(![self.scanner scanString:startDelimeter intoString:nil])
				continue;

			// Scan past end delimiter if possible (a sanity check really, for totally empty tags)
			if([self.scanner scanString:endDelimeter intoString:nil])
				continue;

			// Scan tag content up to end delimeter and scan past end delimeter too if possible
			if([self.scanner scanUpToString:endDelimeter intoString:&tagContent] && [self.scanner scanString:endDelimeter intoString:nil]) {
				// We have some tag content to play with at this point, prepare this content by trimming surrounding whitespace
				DMTemplateTagInfo* tagInfo = [self _analyzeTagContent:tagContent];
				tagContent = tagInfo.content;
				
				@try {
					// Determine tag content type and handle it
					switch(tagInfo.type) {
						case DMTemplateIfTagType: {
								DMTemplateCondition* condition = [DMTemplateCondition condition];
								
								// If we are current skipping this content, mark this new condition as solved. This way other 
								// conditions will naturally skip processing. Otherwise, let us evaluate the tag content.
								if(skipContent)
									condition.result = YES;
								else
									condition.result = [self _evaluateConditionStatement:tagContent];

								// Throw new condition object onto the stack
								[self _pushCondition:condition];
							
								// Skip over a newline, if necessary.
								[self _scanSingleNewline];
							}
							break;
						
						case DMTemplateElseIfTagType: {
								DMTemplateCondition* condition = self.currentCondition;
								
								// If the current condition has already been solved, avoid evaluation by simply ignoring 
								// this condition completely.
								if(condition.isSolved)
									condition.result = NO;
								else
									condition.result = [self _evaluateConditionStatement:tagContent];
							
								// Skip over a newline, if necessary.
								[self _scanSingleNewline];
							}
							break;
						
						case DMTemplateElseTagType: {
								DMTemplateCondition* condition = self.currentCondition;
								
								// If the current condition has already been solved, simply ignore.
								condition.result = (condition.isSolved ? NO : !condition.result);
							
								// Skip over a newline, if necessary.
								[self _scanSingleNewline];
							}
							break;
						
						case DMTemplateEndIfTagType: {
								// End current condition by popping it off the stack.
								[self _popCondition];
							
								// Skip over a newline, if necessary.
								[self _scanSingleNewline];
							}
							break;
						
						case DMTemplateForEachTagType: {
								// Skip over a newline, if necessary.
								[self _scanSingleNewline];
							
								// Read foreach block content, only store if we are not currently skipping over content.
								NSString* blockContent = [self _scanBlockOfType:DMTemplateForEachBlockType returnContent:!skipContent];
								
								if(skipContent)
									continue;
								
								// Evaluate foreach statement
								NSArray* array = [self _evaluateForeachStatement:tagContent];
								if(array == nil)
									continue;
							
								// Enumerate over each object in array and build foreach block content against each.
								for(id obj in array) {
									NSString* builtContent = [[DMTemplateEngine engineWithTemplate:blockContent] renderAgainst:obj];
									if(builtContent != nil)
										[self.renderedTemplate appendString:builtContent];
								}
							}
							break;
						
						case DMTemplateLogTagType: {
								// If we are currently skipping content, don't log.
								if(skipContent)
									continue;
								
								NSString* statementContent = [self _parseStatementContent:tagContent];
								if(([statementContent hasPrefix:@"\""] && [statementContent hasSuffix:@"\""]) || ([statementContent hasPrefix:@"'"] && [statementContent hasSuffix:@"'"])) {
									// Statement is a string, so remove quotes and log what was typed.
									statementContent = [statementContent substringWithRange:NSMakeRange(1, [statementContent length]-2)];
									NSLog(@"%@", statementContent);
								}
								else {
									// Statement (we assume) is a key-value path, find value and log that.
									NSLog(@"%@", [self.object valueForKeyPath:statementContent]);
								}
							
								// Skip over a newline, if necessary.
								[self _scanSingleNewline];
							}
							break;
							
						case DMTemplateValueTagType: {
								// If we are currently skipping content, simply skip this value.
								if(skipContent)
									continue;

								// Get key value for the specified key path. If a value is found, append it to the result.
								id keyValue = [self.object valueForKeyPath:tagContent];
								if(keyValue != nil) {
									NSString* keyString = [keyValue description];
									
									// Run through modifiers and apply.
									for(NSString* modifier in tagInfo.modifiers) {
										NSString*(^modifierBlock)(NSString*) = [self.modifiers objectForKey:modifier];
										if(modifierBlock != nil)
											keyString = modifierBlock(keyString);
									}
									
									// Append modified value to rendering.
									[self.renderedTemplate appendString:keyString];
								}
							}
							break;
					}
				}
				@catch(id exception) {
					NSLog(@"DMTemplateEngine: Build error %@", exception);
				}
			}
		}
		@finally {
			[memoryPool release];
		}
	}
}

- (NSString*)_parseStatementContent:(NSString*)tag {
	// Find open and close brackets surrounding content
	NSRange openBracketRange = [tag rangeOfString:@"("];
	NSRange closeBracketRange = [tag rangeOfString:@")" options:NSBackwardsSearch];
	
	// Make sure open and close brackets were found
	if(openBracketRange.length == 0 || closeBracketRange.length == 0 || closeBracketRange.location <= NSMaxRange(openBracketRange))
		return nil;
	
	// Determine content range
	NSRange conditionContentRange = NSMakeRange(NSMaxRange(openBracketRange), closeBracketRange.location - NSMaxRange(openBracketRange));
	if(conditionContentRange.length == 0)
		return nil;
	
	// Extract content
	NSString* content = [tag substringWithRange:conditionContentRange];
	
	// Prepare content
	content = [DMTemplateEngine _stringByTrimmingWhitespace:content];
	
	// Return null if the content is empty
	if([content length] == 0)
		return nil;
	
	return content;
}

- (NSString*)_scanBlockOfType:(DMTemplateBlockType)inType returnContent:(BOOL)returnContent {
	NSMutableString* content = [NSMutableString string];
	unsigned nestLevel = 0;
	
	while(![self.scanner isAtEnd]) {
		NSString* tagContent = nil;
		NSString* scannedText = nil;

		// Scan contents up to the first start delimeter we can find
		if([self.scanner scanUpToString:self.beginProcessorMarker intoString:(returnContent ? &scannedText : nil)]) {
			// Append scanned content to result if we are not skipping this content
			if(returnContent) {
				[content appendString:scannedText];
			}
		}

		// Scan past start delimeter if possible
		if(![self.scanner scanString:self.beginProcessorMarker intoString:nil])
			continue;

		// Scan past end delimiter if possible (a sanity check really, for totally empty tags
		if([self.scanner scanString:self.endProcessorMarker intoString:nil])
			continue;

		// Scan tag content up to end delimeter and scan past end delimeter too if possible
		if([self.scanner scanUpToString:self.endProcessorMarker intoString:&tagContent] && [self.scanner scanString:self.endProcessorMarker intoString:nil]) {
			// We have some tag content to play with at this point, prepare this content by trimming surrounding whitespace
			tagContent = [DMTemplateEngine _stringByTrimmingWhitespace:tagContent];
			
			DMTemplateTagType tagType = [self _determineTemplateTagType:tagContent];
			
			if((inType == DMTemplateIfBlockType && tagType == DMTemplateIfTagType) || (inType == DMTemplateForEachBlockType && tagType == DMTemplateForEachTagType))
				nestLevel++;
			else
			if((inType == DMTemplateIfBlockType && tagType == DMTemplateEndIfTagType) || (inType == DMTemplateForEachBlockType && tagType == DMTemplateEndForEachTagType)) {
				if(nestLevel == 0) {
					[self _scanSingleNewline];
					break;
				}
				else
					nestLevel--;
			}
			
			if(returnContent)
				[content appendFormat:@"%@ %@ %@", self.beginProcessorMarker, tagContent, self.endProcessorMarker];
		}
	}
	
	return content;
}

- (BOOL)_scanSingleNewline {
	// Pass on this scan if the scanner is done.
	if([self.scanner isAtEnd])
		return NO;
	
	NSUInteger loc = [self.scanner scanLocation];
	unichar character = [[self.scanner string] characterAtIndex:[self.scanner scanLocation]];
	
	// If this character is not part of the newline
	// character set, then we're not going to skip it.
	if(![[NSCharacterSet newlineCharacterSet] characterIsMember:character])
		return NO;
	
	// If this character is part of the newline set
	// then let's skip over it.
	[self.scanner setScanLocation:loc+1];
	
	return YES;
}

- (NSArray*)_evaluateForeachStatement:(NSString*)tag {
	// Tag content must be at least 10 characters in length.
	if([tag length] < [@"foreach( )" length])
		return nil;
	
	// Parse statement content
	NSString* statementContent = [self _parseStatementContent:tag];
	if(statementContent == nil)
		return nil;
	
	NSArray* array = nil;
	
	@try {
		if([statementContent hasPrefix:@"{"] && [statementContent hasSuffix:@"}"]) {
			// Statement is an inline array
			statementContent = [statementContent substringWithRange:NSMakeRange(1, [statementContent length]-2)];
			if([statementContent length] == 0)
				return nil;
			
			// We are using property list serialization to convert inline array strings into NSArrays.
			// This just happens to work because old-style property list array syntax is exactly 
			// what we want, so (because I'm lazy) we simply use a built-in parser which requires the 
			// content to be wrapped in parens.
			
			statementContent = [NSString stringWithFormat:@"(%@)", statementContent];
			
			NSPropertyListFormat propertyListFormat;
			NSString* propertyListError;
		
			// Deserialize inline array and return.
			id propertyList = [NSPropertyListSerialization propertyListFromData:[statementContent dataUsingEncoding:NSUTF8StringEncoding] mutabilityOption:NSPropertyListImmutable format:&propertyListFormat errorDescription:&propertyListError];
			if(propertyList && [propertyList isKindOfClass:[NSArray class]])
				array = (NSArray*)propertyList;
		}
		else {
			// Statement is (we assume) a key-value path, so try to get the value and make sure it is an array.
			id keyValue = [self.object valueForKeyPath:statementContent];
			if(keyValue != nil && [keyValue isKindOfClass:[NSArray class]])
				array = (NSArray*)keyValue;
		}
	}
	@catch(id exception) {
		array = nil;
	}
	
	return array;
}

- (BOOL)_evaluateConditionStatement:(NSString*)tag {
	// Tag content must be at least 5 characters in length.
	if([tag length] < [@"if( )" length])
		return NO;
	
	// Parse condition content
	NSString* conditionContent = [self _parseStatementContent:tag];
	if(conditionContent == nil)
		return NO;
	
	BOOL result = NO;
	
	@try {
		// Compile and evaluate predicate
		result = [[NSPredicate predicateWithFormat:conditionContent] evaluateWithObject:self.object];
	}
	@catch(id exception) {
		// Predicate failed to compile, probably a syntax error.
		result = NO;
	}

	return result;
}

- (DMTemplateTagInfo*)_analyzeTagContent:(NSString*)content {
	DMTemplateTagInfo* tagInfo = [DMTemplateTagInfo tagInfo];
	
	content = [DMTemplateEngine _stringByTrimmingWhitespace:content];

	if([content hasPrefix:@"["]) {
		NSRange optionsRange;
		
		optionsRange = [content rangeOfString:@"]"];
		optionsRange.length = optionsRange.location-1;
		optionsRange.location = 1;
		
		NSString* optionsContent = [content substringWithRange:optionsRange];
		optionsContent = [DMTemplateEngine _stringByRemovingCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] string:optionsContent];
		optionsContent = [optionsContent lowercaseString];
		
		for(NSUInteger i = 0; i < [optionsContent length]; i++) {
			unichar modifierChar = [optionsContent characterAtIndex:i];
			NSString* modifierString = [NSString stringWithCharacters:&modifierChar length:1];
			[tagInfo.modifiers addObject:modifierString];
		}
		
		content = [content substringFromIndex:NSMaxRange(optionsRange)+1];
		content = [DMTemplateEngine _stringByTrimmingWhitespace:content];
	}
	
	tagInfo.type = [self _determineTemplateTagType:content];
	tagInfo.content = content;
	
	return tagInfo;
}

- (DMTemplateTagType)_determineTemplateTagType:(NSString*)tag {
	DMTemplateTagType tagType;
	
	if([tag isCaseInsensitiveLike:@"if*(*"]) {
		// Tag is an if statement
		// e.g. if(condition)
		tagType = DMTemplateIfTagType;
	}
	else
	if([tag isCaseInsensitiveLike:@"else"]) {
		// Tag is a simple else statement
		// e.g. else
		tagType = DMTemplateElseTagType;
	}
	else
	if([tag isCaseInsensitiveLike:@"elseif*(*"]) {
		// Tag is an alternative if statement
		// e.g. elseif(condition)
		tagType = DMTemplateElseIfTagType;
	}
	else
	if([tag isCaseInsensitiveLike:@"endif"]) {
		// Tag is a closing if statement
		// e.g. endif
		tagType = DMTemplateEndIfTagType;
	}
	else
	if([tag isCaseInsensitiveLike:@"foreach*(*"]) {
		// Tag is a foreach statement
		// e.g. foreach(array)
		tagType = DMTemplateForEachTagType;
	}
	else
	if([tag isCaseInsensitiveLike:@"endforeach"]) {
		// Tag is a closing foreach statement
		// e.g. endforeach
		tagType = DMTemplateEndForEachTagType;
	}
	else
	if([tag isCaseInsensitiveLike:@"log*(*"]) {
		// Tag is a log statement
		// e.g. log
		tagType = DMTemplateLogTagType;
	}
	else {
		// Tag is a value to be substituted
		tagType = DMTemplateValueTagType;
	}
	
	return tagType;
}

#pragma mark -
#pragma mark Conditions

- (void)_pushCondition:(DMTemplateCondition*)condition {
	[self.conditionStack addObject:condition];
}

- (void)_popCondition {
	[self.conditionStack removeLastObject];
}

@end

#pragma mark -

@implementation DMTemplateCondition

@synthesize isSolved;
@synthesize result;

#pragma mark -

+ (id)condition {
	return [[[DMTemplateCondition alloc] init] autorelease];
}

- (id)init {
	self = [super init];
	if(self == nil)
		return nil;
	
	isSolved = NO;
	result = NO;
	
	return self;
}

- (void)setConditionResult:(BOOL)flag {
	result = flag;
	if(flag)
		isSolved = YES;
}

@end

#pragma mark -

@implementation DMTemplateTagInfo

@synthesize type;
@synthesize modifiers;
@synthesize content;

#pragma mark -

+ (id)tagInfo {
	return [[[DMTemplateTagInfo alloc] init] autorelease];
}

- (id)init {
	self = [super init];
	if(self == nil)
		return nil;
	
	self.modifiers = [NSMutableArray array];
	
	return self;
}

- (void)dealloc {
	self.modifiers = nil;
	self.content = nil;
	[super dealloc];
}

@end

#pragma mark -

@implementation DMTemplateEngine (Strings)

+ (NSString*)_stringWithReadableByteSize:(unsigned long long)bytes {
	double kb, mb, gb, tb, pb;
	
	// Handle bytes
	if(bytes < 1000)
		return [NSString stringWithFormat:@"%d B", (int)bytes];
	
	// Handle kilobytes
	kb = bytes / 1024.0;
	if(kb < 1000.0)
		return [NSString stringWithFormat:@"%0.1f KB", kb];
	
	// Handle megabytes
	mb = kb / 1024.0;
	if(mb < 1000.0)
		return [NSString stringWithFormat:@"%0.1f MB", mb];
	
	// Handle gigabytes
	gb = mb / 1024.0;
	if(gb < 1000.0)
		return [NSString stringWithFormat:@"%0.1f GB", gb];
	
	// Handle terabytes
	tb = gb / 1024.0;
	if(tb < 1000.0)
		return [NSString stringWithFormat:@"%0.1f TB", tb];
	
	// Handle petabytes
	pb = tb / 1024.0;
	return [NSString stringWithFormat:@"%0.1f PB", pb];
}

+ (NSString*)_stringByEscapingXMLEntities:(NSString*)string {
	static const unichar nbsp = 0xA0;
	NSDictionary* entities = [NSDictionary dictionaryWithObjectsAndKeys:
														@"amp", @"&",
														@"lt", @"<",
														@"gt", @">", 
														@"quot", @"\"",
														@"apos", @"'",
														@"nbsp", [NSString stringWithCharacters:&nbsp length:1],
														@"#x09", @"\t",
														@"#x0A", @"\n",
														@"#x0B", @"\v",
														@"#x0C", @"\f",
														@"#x0D", @"\r",
														nil
														];
	
	return [(NSString*)CFXMLCreateStringByEscapingEntities(kCFAllocatorDefault, (CFStringRef)string, (CFDictionaryRef)entities) autorelease];
}

+ (NSString*)_stringByAddingPercentEscapes:(NSString*)string {
	return [(NSString*)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)string, CFSTR(""), CFSTR("/"), kCFStringEncodingUTF8) autorelease];
}

+ (NSString*)_stringByRemovingCharactersFromSet:(NSCharacterSet*)set string:(NSString*)string {
	NSMutableString* result;
	
	if([string rangeOfCharacterFromSet:set options:NSLiteralSearch].length == 0)
		return string;
	
	result = [[string mutableCopyWithZone:[string zone]] autorelease];
	[self _removeCharactersInSet:set string:result];
	
	return result;
}

+ (NSString*)_stringByTrimmingWhitespace:(NSString*)string {
	return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (void)_removeCharactersInSet:(NSCharacterSet*)set string:(NSMutableString*)string {
	NSRange matchRange, searchRange, replaceRange;
	unsigned int length;
	
	length = [string length];
	matchRange = [string rangeOfCharacterFromSet:set options:NSLiteralSearch range:NSMakeRange(0, length)];
	while(matchRange.length > 0) {
		replaceRange = matchRange;
		searchRange.location = NSMaxRange(replaceRange);
		searchRange.length = length - searchRange.location;
		
		while(YES) {
			matchRange = [string rangeOfCharacterFromSet:set options:NSLiteralSearch range:searchRange];
			if((matchRange.length == 0) || (matchRange.location != searchRange.location))
				break;
			
			replaceRange.length += matchRange.length;
			searchRange.length -= matchRange.length;
			searchRange.location += matchRange.length;
		}
		
		[string deleteCharactersInRange:replaceRange];
		matchRange.location -= replaceRange.length;
		length -= replaceRange.length;
	}
}

@end