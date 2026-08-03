#import <Cocoa/Cocoa.h>
#include <CoreGraphics/CoreGraphics.h>

#define GLFW_EXPOSE_NATIVE_COCOA

#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

extern void zig_gui_draw(void *render_state, void *context, double width,
                         double height);

@interface ZigGuiView : NSView
@property(nonatomic, assign) void *renderState;
@end

@implementation ZigGuiView
- (BOOL)isFlipped {
  return YES;
}

- (NSView *)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}

- (BOOL)isOpaque {
  return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;

  CGContextRef context = [[NSGraphicsContext currentContext] CGContext];

  zig_gui_draw(self.renderState, (void *)context, self.bounds.size.width,
               self.bounds.size.height);
}

@end

void *gui_macos_attach(void *raw_window, void *raw_render_state) {
  GLFWwindow *window = (GLFWwindow *)raw_window;

  NSView *glfw_view = glfwGetCocoaView(window);

  ZigGuiView *view = [[ZigGuiView alloc] initWithFrame:glfw_view.bounds];
  view.renderState = raw_render_state;

  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  [glfw_view addSubview:view];

  return (__bridge_retained void *)view;
}

void gui_macos_redraw(void *raw_view) {
  ZigGuiView *view = (__bridge ZigGuiView *)raw_view;

  view.needsDisplay = YES;
}

void gui_macos_detach(void *raw_view) {
  ZigGuiView *view = (__bridge_transfer ZigGuiView *)raw_view;
  view.renderState = NULL;

  [view removeFromSuperview];
}
