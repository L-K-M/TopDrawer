// CGtk4: the GTK4 C API, resolved through pkg-config's `gtk4` flags (SwiftPM passes
// pkg-config's include paths when building this [system] module). One umbrella shim
// rather than per-header modules — GTK is one API in practice, and dexbar proves the
// umbrella import compiles from Swift.
#include <gtk/gtk.h>
