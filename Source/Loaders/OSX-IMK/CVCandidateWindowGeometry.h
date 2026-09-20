#ifndef CV_CANDIDATE_WINDOW_GEOMETRY_H
#define CV_CANDIDATE_WINDOW_GEOMETRY_H

#import <Cocoa/Cocoa.h>

// Scale the content as requested until its required dimensions reach the
// screen. A vertical panel can pass the height of its fixed controls and one
// row, then scroll the remaining rows within that screen-sized window.
static inline CGFloat CVFitCandidateScale(NSSize requiredContentSize,
                                          NSRect visibleFrame,
                                          CGFloat requestedScale)
{
    if (requiredContentSize.width <= 0 || requiredContentSize.height <= 0 ||
        visibleFrame.size.width <= 0 || visibleFrame.size.height <= 0)
        return requestedScale;

    return MIN(requestedScale,
               MIN(visibleFrame.size.width / requiredContentSize.width,
                   visibleFrame.size.height / requiredContentSize.height));
}

static inline NSRect CVPlaceCandidateWindow(NSPoint caret,
                                             NSSize scaledSize,
                                             NSRect visibleFrame,
                                             CGFloat fontHeight)
{
    NSSize size = NSMakeSize(MIN(scaledSize.width, visibleFrame.size.width),
                             MIN(scaledSize.height, visibleFrame.size.height));
    CGFloat x = MIN(MAX(caret.x, NSMinX(visibleFrame)), NSMaxX(visibleFrame) - size.width);
    CGFloat below = caret.y - size.height;
    CGFloat y = below >= NSMinY(visibleFrame) ? below : caret.y + fontHeight;
    y = MIN(MAX(y, NSMinY(visibleFrame)), NSMaxY(visibleFrame) - size.height);
    return NSMakeRect(x, y, size.width, size.height);
}

#endif
