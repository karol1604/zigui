#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#define GLFW_EXPOSE_NATIVE_COCOA

#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

@interface ZigGuiMetalView : NSView
@end

@implementation ZigGuiMetalView

- (BOOL)isFlipped {
  return YES;
}

- (NSView *)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}

- (BOOL)isOpaque {
  return YES;
}

@end

void *gui_macos_attach(void *raw_window, void *raw_metal_layer) {
  GLFWwindow *window = (GLFWwindow *)raw_window;
  NSView *glfw_view = glfwGetCocoaView(window);
  CAMetalLayer *layer = (__bridge CAMetalLayer *)raw_metal_layer;

  ZigGuiMetalView *view =
      [[ZigGuiMetalView alloc] initWithFrame:glfw_view.bounds];
  if (view == nil) {
    return NULL;
  }

  view.wantsLayer = YES;
  view.layer = layer;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  layer.opaque = YES;

  [glfw_view addSubview:view];

  CGFloat scale = glfw_view.window.backingScaleFactor;
  layer.contentsScale = scale;
  layer.drawableSize = CGSizeMake(view.bounds.size.width * scale,
                                  view.bounds.size.height * scale);

  return (__bridge_retained void *)view;
}

void gui_macos_resize_drawable(void *raw_view, size_t width, size_t height) {
  ZigGuiMetalView *view = (__bridge ZigGuiMetalView *)raw_view;
  CAMetalLayer *layer = (CAMetalLayer *)view.layer;

  layer.contentsScale = view.window.backingScaleFactor;
  layer.drawableSize = CGSizeMake((CGFloat)width, (CGFloat)height);
}

void gui_macos_detach(void *raw_view) {
  ZigGuiMetalView *view = (__bridge_transfer ZigGuiMetalView *)raw_view;
  [view removeFromSuperview];
}
