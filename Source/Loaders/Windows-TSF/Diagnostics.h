#pragma once

namespace KeyKey::WindowsTsf {

bool DiagnosticsEnabled();
void RefreshDiagnosticsSettings();
void Trace(const char* format, ...);

}  // namespace KeyKey::WindowsTsf
