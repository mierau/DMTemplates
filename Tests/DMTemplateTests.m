
// DMTemplateTests.m
// Dustin Mierau
// Cared for under the MIT license.

#import <XCTest/XCTest.h>
#import <CommonCrypto/CommonDigest.h>
#import "DMTemplateEngine.h"

@interface DMTemplateTests : XCTestCase
@property (nonatomic, retain) DMTemplateEngine* engine;
@end

#pragma mark -

@implementation DMTemplateTests

- (void)setUp {
	[super setUp];
	self.engine = [DMTemplateEngine engine];
}

- (void)tearDown {
	[super tearDown];
}

#pragma mark -

- (void)testEmptyTemplates {
	// Test completely empty template.
	_engine.template = @"";
	XCTAssertEqualObjects([_engine renderAgainst:nil], @"", @"Empty template should render an empty string.");
	
	// Test template with just whitespace.
	_engine.template = @"  ";
	XCTAssertEqualObjects([_engine renderAgainst:nil], @"  ", @"Empty template should render an empty string.");
	
	// Test template with whitespace and a newline.
	_engine.template = @" \n";
	XCTAssertEqualObjects([_engine renderAgainst:nil], @" \n", @"Empty template should render an empty string.");
	
	// Test template with a newline and whitespace.
	_engine.template = @"\n ";
	XCTAssertEqualObjects([_engine renderAgainst:nil], @"\n ", @"Empty template should render an empty string.");
}

- (void)testBuiltInModifiers {
	// Create some test data to render against.
	NSMutableDictionary* templateData = [NSMutableDictionary dictionary];
	
	// Test human readable byte size modifier.
	_engine.template = @"{%[b] fileSize %}";
	
	[templateData setObject:@"0" forKey:@"fileSize"];
	XCTAssertEqualObjects([_engine renderAgainst:templateData], @"0 B", @"Zero bytes should be handled.");
	
	[templateData setObject:@"51" forKey:@"fileSize"];
	XCTAssertEqualObjects([_engine renderAgainst:templateData], @"51 B", @"Bytes should be handled.");
	
	[templateData setObject:@"2300" forKey:@"fileSize"];
	XCTAssertEqualObjects([_engine renderAgainst:templateData], @"2.2 KB", @"Kilobytes should be handled.");
	
	[templateData setObject:@"2034421" forKey:@"fileSize"];
	XCTAssertEqualObjects([_engine renderAgainst:templateData], @"1.9 MB", @"Megabytes should be handled.");
	
	[templateData setObject:@"9824958720" forKey:@"fileSize"];
	XCTAssertEqualObjects([_engine renderAgainst:templateData], @"9.2 GB", @"Gigabytes should be handled.");
	
	[templateData setObject:@"89823871822003" forKey:@"fileSize"];
	XCTAssertEqualObjects([_engine renderAgainst:templateData], @"81.7 TB", @"Terabytes should be handled.");
	
	// Test URL encoding modifier.
	_engine.template = @"{%[u] name %}";
	[templateData setObject:@"Düstinø Mîeråü" forKey:@"name"];
	XCTAssertEqualObjects([_engine renderAgainst:templateData], @"D%C3%BCstin%C3%B8%20M%C3%AEer%C3%A5%C3%BC", @"Zero bytes should be handled.");
	
	// Test XML escape modifier.
	_engine.template = @"{%[e] xml %}";
	[templateData setObject:@"<this>is some & \"xml\"</this>" forKey:@"xml"];
	XCTAssertEqualObjects([_engine renderAgainst:templateData], @"&lt;this&gt;is some &amp; &quot;xml&quot;&lt;/this&gt;", @"XML should be properly escaped.");
}

- (void)testCustomModifiers {
	DMTemplateEngine* engine = [DMTemplateEngine engine];
	
	// Remove built-in modifiers.
	[engine removeAllModifiers];
	
	// Add a custom whitespace trimming modifier for 'w'.
	[engine addModifier:'w' block:^(NSString* content) {
		return [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}];
	
	// Add a custom md5 modifier for 'm'.
	[engine addModifier:'m' block:^(NSString* content) {
		const char* string = [content UTF8String];
		unsigned char hash[16];
		
		// Calculate MD5.
		CC_MD5((void*)string, (CC_LONG)strlen(string), hash);
		
		// Build hex encoded MD5 string.
		NSString* md5 = [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X", hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7], hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]];
		return md5;
	}];
	
	// Create some test data to render against.
	NSMutableDictionary* templateData = [NSMutableDictionary dictionary];
	[templateData setObject:@"  \nDustin " forKey:@"firstNameWithWhitespace"];
	[templateData setObject:@"Dustin" forKey:@"firstName"];
	[templateData setObject:@"Mierau" forKey:@"lastName"];
	
	// Run our MD5 modifier on our first name sans-whitespace.
	engine.template = @"{%[m] firstName %}";
	XCTAssertEqualObjects([engine renderAgainst:templateData], @"7E3FCEB10594A451E0741D4C536646FB", @"");
	
	// Running our MD5 modifier on our first name with whitespace
	// after using our whitespace trimming modifier should produce
	// the same MD5.
	engine.template = @"{%[wm] firstNameWithWhitespace %}";
	XCTAssertEqualObjects([engine renderAgainst:templateData], @"7E3FCEB10594A451E0741D4C536646FB", @"");
	
	// Modifiers should run in order specified. So, running MD5 on on
	// the whitespace ridden first name should produce an MD5
	// different than the first.
	engine.template = @"{%[mw] firstNameWithWhitespace %}";
	XCTAssertEqualObjects([engine renderAgainst:templateData], @"EE6E7B3FB4E475E4F6999DE3E9BB39CB", @"");
}

@end
