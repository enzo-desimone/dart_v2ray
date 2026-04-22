#ifndef DART_V2RAY_LIBXRAYBRIDGE_H_
#define DART_V2RAY_LIBXRAYBRIDGE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t XrayStartFromConfigPath(const char* configPath);
int32_t XrayStartFromConfigJson(const char* configJSON);
int32_t XrayStop(void);
char* XrayVersion(void);
char* XrayLastError(void);
void XrayFreeString(char* value);

#ifdef __cplusplus
}
#endif

#endif  // DART_V2RAY_LIBXRAYBRIDGE_H_
