// Aro currently detects Apple's target-conditional extension without defining
// the macOS conditionals that Apple's umbrella headers expect.
#ifndef TARGET_OS_MAC
#define TARGET_OS_MAC 1
#endif

#ifndef TARGET_OS_OSX
#define TARGET_OS_OSX 1
#endif

#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
