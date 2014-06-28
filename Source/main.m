
// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

#import "DMTemplateEngine.h"

int main(int argc, const char* argv[]) {
	NSUserDefaults* args = [NSUserDefaults standardUserDefaults];
	NSURL* templateURL = [args URLForKey:@"template"];
	NSURL* plistURL = [args URLForKey:@"plist"];
	
	// Use default template if none other was specified.
	if(templateURL == nil) {
		NSString* templatePath = [[[[NSString stringWithCString:__FILE__ encoding:NSUTF8StringEncoding] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Example/ExampleTemplate.txt"];
		
		templateURL = [NSURL fileURLWithPath:templatePath];
	}
	
	// Make sure the specified template file exists.
	if(![[NSFileManager defaultManager] fileExistsAtPath:[templateURL relativePath]]) {
		printf("Specified template file does not exist.");
		return 1;
	}
	
	// Use default template data if none other was specified.
	if(plistURL == nil) {
		NSString* dataPath = [[[[NSString stringWithCString:__FILE__ encoding:NSUTF8StringEncoding] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Example/ExampleData.plist"];
		plistURL = [NSURL fileURLWithPath:dataPath];
	}
	
	// Make sure the specified template data file exists.
	if(![[NSFileManager defaultManager] fileExistsAtPath:[plistURL relativePath]]) {
		printf("Specified property list file does not exist.");
		return 1;
	}
	
	// Read template into string from disk.
	NSError* templateError = nil;
	NSStringEncoding templateEncoding;
	NSString* templateString = [NSString stringWithContentsOfURL:templateURL usedEncoding:&templateEncoding error:&templateError];
	
	// Read property list into dictionary from disk.
	NSMutableDictionary* templateData = [NSMutableDictionary dictionaryWithContentsOfURL:plistURL];
	
	// Render template against dictionary.
	NSString* rendered = [[DMTemplateEngine engineWithTemplate:templateString] renderAgainst:templateData];
	
	// Output rendered template.
	printf("%s", [rendered cStringUsingEncoding:templateEncoding]);
	
	return 0;
}
