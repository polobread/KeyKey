// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../LICENSE.txt.
// Evaluate the actual distribution preflight with fake hardware and package strings.
#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

static int passed;
static void Check(BOOL value, NSString *message)
{
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
    passed++;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        Check(argc == 2, @"installer directory is supplied");
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        NSError *error = nil;
        NSXMLDocument *document = [[[NSXMLDocument alloc] initWithContentsOfURL:
            [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"distribution.plist"]]
            options:0 error:&error] autorelease];
        Check(document != nil, [NSString stringWithFormat:@"distribution parses: %@", error]);
        NSArray *options = [document nodesForXPath:@"/installer-gui-script/options" error:&error];
        Check(options.count == 1, @"one Installer execution policy is declared");
        NSSet *hosts = [NSSet setWithArray:[[(NSXMLElement *)options[0]
            attributeForName:@"hostArchitectures"].stringValue componentsSeparatedByString:@","]];
        Check([hosts containsObject:@"arm64"], @"Apple Silicon evaluates the installer without Rosetta");
        Check([hosts containsObject:@"x86_64"], @"Intel can reach the localized hardware rejection");
        NSArray *scripts = [document nodesForXPath:@"/installer-gui-script/script" error:&error];
        NSArray *checks = [document nodesForXPath:@"/installer-gui-script/installation-check" error:&error];
        Check(scripts.count == 1 && checks.count == 1, @"one host preflight is wired");
        NSString *code = [scripts[0] stringValue];
        NSString *expression = [(NSXMLElement *)checks[0] attributeForName:@"script"].stringValue;
        Check(expression.length > 0, @"Installer invokes the preflight expression");

        for (NSString *language in @[@"English", @"zh_TW"]) {
            NSString *stringsPath = [root stringByAppendingPathComponent:
                [NSString stringWithFormat:@"Resources/%@.lproj/Localizable.strings", language]];
            NSDictionary *strings = [NSDictionary dictionaryWithContentsOfFile:stringsPath];
            Check(strings.count > 0, @"package translations load");
            // Include string-valued sysctl results and a missing/throwing selector.
            for (id capability in @[@1, @"1", @0, @"0", [NSNull null], @"throws"]) {
                JSContext *context = [[[JSContext alloc] init] autorelease];
                context[@"system"] = @{
                    @"sysctl": ^id(NSString *selector) {
                        Check([selector isEqual:@"hw.optional.arm64"], @"checks hardware capability");
                        if ([capability isEqual:@"throws"]) {
                            [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:
                                @"selector unavailable" inContext:[JSContext currentContext]];
                            return nil;
                        }
                        return capability;
                    },
                    @"localizedString": ^id(NSString *key) { return strings[key]; }
                };
                [context evaluateScript:@"var my = { result: {} }; "];
                [context evaluateScript:code];
                JSValue *result = [context evaluateScript:expression];
                Check(context.exception == nil, @"preflight handles unavailable hardware without an exception");
                BOOL supported = [capability isEqual:@1] || [capability isEqual:@"1"];
                Check(result.toBool == supported, @"only Apple Silicon may proceed");
                JSValue *details = context[@"my"][@"result"];
                if (supported) {
                    Check(details[@"type"].isUndefined, @"supported host has no failure message");
                } else {
                    Check([[details[@"type"] toString] isEqual:@"Fatal"], @"unsupported host cannot continue");
                    Check([[details[@"title"] toString] isEqual:strings[@"AppleSiliconRequiredTitle"]],
                          @"failure title comes from this package's localization");
                    NSString *message = [details[@"message"] toString];
                    Check([message isEqual:strings[@"AppleSiliconRequiredMessage"]] &&
                          [message containsString:@"Apple"] && [message containsString:@"Intel"],
                          @"failure explains both the required hardware and Intel exclusion");
                }
            }
        }
        NSLog(@"PASS: %d distribution checks (fake hardware; no installation)", passed);
    }
}
