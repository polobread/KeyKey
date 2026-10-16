/*
Copyright (c) 2012, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. See the accompanying LICENSE
file for terms.
*/

#import "TakaoAbout.h"
#import "TakaoWordCount.h"

static NSString *const KKProjectURL = @"https://github.com/polobread/KeyKey";
static NSString *const KKLatestReleaseURL = @"https://github.com/polobread/KeyKey/releases/latest";

@interface KKAboutDocumentView : NSView
@end
@implementation KKAboutDocumentView
- (BOOL)isFlipped { return YES; }
@end

@implementation TakaoAbout

- (id)initWithModuleInfo:(NSArray *)modules
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        for (NSDictionary *module in modules) {
            if ([module[OVServiceLoadedModulePackageIdentifierKey] isEqualToString:@"YKAFWordCount"] &&
                [module[OVServiceLoadedModulePackageEnabledKey] boolValue]) {
                _wordCountController = [[TakaoWordCount alloc] init];
                break;
            }
        }
    }
    return self;
}

- (void)dealloc
{
    [_wordCountController release];
    [super dealloc];
}

- (void)loadView
{
    // Preferences is nested in the IMK app. Show the enclosing product's
    // version, with the standalone Preferences bundle as a development fallback.
    NSBundle *product = [NSBundle mainBundle];
    NSURL *parent = product.bundleURL;
    for (NSUInteger i = 0; i < 3; i++) parent = parent.URLByDeletingLastPathComponent;
    NSBundle *host = [NSBundle bundleWithURL:parent];
    if ([host.bundleIdentifier isEqualToString:@"io.github.polobread.inputmethod.chichi77"])
        product = host;
    NSString *version = [product objectForInfoDictionaryKey:@"KeyKeyReleaseVersion"] ?:
        [product objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"—";

    NSView *view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 520)] autorelease];
    self.view = view;
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:view.bounds] autorelease];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    [view addSubview:scroll];
    NSView *document = [[[KKAboutDocumentView alloc] initWithFrame:NSZeroRect] autorelease];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = document;
    [NSLayoutConstraint activateConstraints:@[
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor]
    ]];
    NSStackView *stack = [[[NSStackView alloc] initWithFrame:NSZeroRect] autorelease];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-28],
        [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-24]
    ]];

    NSImageView *icon = [NSImageView imageViewWithImage:NSApp.applicationIconImage];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:80],
        [icon.heightAnchor constraintEqualToConstant:80]
    ]];
    [stack addArrangedSubview:icon];

    NSTextField *name = [NSTextField labelWithString:NSLocalizedString(@"chichi77 KeyKey", nil)];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    name.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
    [stack addArrangedSubview:name];
    NSTextField *versionLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:NSLocalizedString(@"Version %@", nil), version]];
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    versionLabel.textColor = NSColor.secondaryLabelColor;
    versionLabel.selectable = YES;
    [stack addArrangedSubview:versionLabel];

    NSButton *project = [NSButton buttonWithTitle:NSLocalizedString(@"GitHub Project", nil)
        target:self action:@selector(openProject:)];
    project.translatesAutoresizingMaskIntoConstraints = NO;
    project.toolTip = KKProjectURL;
    NSButton *release = [NSButton buttonWithTitle:NSLocalizedString(@"Latest Release", nil)
        target:self action:@selector(openLatestRelease:)];
    release.translatesAutoresizingMaskIntoConstraints = NO;
    release.toolTip = KKLatestReleaseURL;
    NSStackView *links = [NSStackView stackViewWithViews:@[project, release]];
    links.translatesAutoresizingMaskIntoConstraints = NO;
    links.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    links.spacing = 12;
    [stack addArrangedSubview:links];

    NSTextField *heading = [NSTextField labelWithString:NSLocalizedString(@"Development Motivation", nil)];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    heading.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    [heading.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [stack addArrangedSubview:heading];

    NSURL *motivationURL = [[NSBundle mainBundle] URLForResource:@"ProjectMotivation" withExtension:@"txt"];
    NSString *motivation = motivationURL
        ? [NSString stringWithContentsOfURL:motivationURL encoding:NSUTF8StringEncoding error:NULL] : nil;
    motivation = [motivation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        ?: NSLocalizedString(@"Unable to load the project introduction.", nil);
    NSTextField *introduction = [NSTextField wrappingLabelWithString:motivation];
    introduction.translatesAutoresizingMaskIntoConstraints = NO;
    introduction.selectable = YES;
    introduction.maximumNumberOfLines = 0;
    NSMutableParagraphStyle *paragraph = [[[NSMutableParagraphStyle alloc] init] autorelease];
    paragraph.lineSpacing = 4;
    introduction.attributedStringValue = [[[NSAttributedString alloc] initWithString:motivation attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:14],
        NSForegroundColorAttributeName: NSColor.labelColor,
        NSParagraphStyleAttributeName: paragraph
    }] autorelease];
    [introduction.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [introduction setContentCompressionResistancePriority:NSLayoutPriorityRequired
        forOrientation:NSLayoutConstraintOrientationVertical];
    [stack addArrangedSubview:introduction];

    NSTextField *credits = [NSTextField wrappingLabelWithString:NSLocalizedString(@"KeyKey Source Credits", nil)];
    credits.translatesAutoresizingMaskIntoConstraints = NO;
    credits.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    credits.textColor = NSColor.secondaryLabelColor;
    credits.alignment = NSTextAlignmentCenter;
    credits.selectable = YES;
    [credits.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [stack addArrangedSubview:credits];

    if (_wordCountController) {
        NSView *counts = [_wordCountController view];
        counts.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [counts.widthAnchor constraintEqualToConstant:260],
            [counts.heightAnchor constraintEqualToConstant:100]
        ]];
        [stack addArrangedSubview:counts];
    }
}

- (void)refresh
{
    [_wordCountController update];
}

- (void)openProject:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:KKProjectURL]];
}

- (void)openLatestRelease:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:KKLatestReleaseURL]];
}

@end
