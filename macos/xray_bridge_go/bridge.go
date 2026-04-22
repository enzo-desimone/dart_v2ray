package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"bytes"
	"fmt"
	"os"
	"sync"
	"unsafe"

	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/distro/all"
)

var (
	instanceMu sync.Mutex
	instance   *core.Instance
	lastErr    string
)

func setLastError(err error) {
	if err == nil {
		lastErr = ""
		return
	}
	lastErr = err.Error()
}

func loadConfigFromJSON(configJSON string) (*core.Config, error) {
	if configJSON == "" {
		return nil, fmt.Errorf("xray config JSON is empty")
	}
	return core.LoadConfig("json", bytes.NewBufferString(configJSON))
}

func startWithConfig(config *core.Config) C.int {
	if config == nil {
		setLastError(fmt.Errorf("xray config is nil"))
		return 1
	}

	if instance != nil {
		_ = instance.Close()
		instance = nil
	}

	server, err := core.New(config)
	if err != nil {
		setLastError(fmt.Errorf("core.New failed: %w", err))
		return 2
	}

	if err := server.Start(); err != nil {
		_ = server.Close()
		setLastError(fmt.Errorf("core.Start failed: %w", err))
		return 3
	}

	instance = server
	setLastError(nil)
	return 0
}

//export XrayStartFromConfigJson
func XrayStartFromConfigJson(configJSON *C.char) C.int {
	instanceMu.Lock()
	defer instanceMu.Unlock()

	if configJSON == nil {
		setLastError(fmt.Errorf("configJSON pointer is nil"))
		return 10
	}

	config, err := loadConfigFromJSON(C.GoString(configJSON))
	if err != nil {
		setLastError(fmt.Errorf("LoadConfig(json) failed: %w", err))
		return 11
	}

	return startWithConfig(config)
}

//export XrayStartFromConfigPath
func XrayStartFromConfigPath(configPath *C.char) C.int {
	instanceMu.Lock()
	defer instanceMu.Unlock()

	if configPath == nil {
		setLastError(fmt.Errorf("configPath pointer is nil"))
		return 20
	}

	path := C.GoString(configPath)
	if path == "" {
		setLastError(fmt.Errorf("configPath is empty"))
		return 21
	}

	payload, err := os.ReadFile(path)
	if err != nil {
		setLastError(fmt.Errorf("cannot read config file %q: %w", path, err))
		return 22
	}

	config, err := loadConfigFromJSON(string(payload))
	if err != nil {
		setLastError(fmt.Errorf("LoadConfig(json) failed for %q: %w", path, err))
		return 23
	}

	return startWithConfig(config)
}

//export XrayStop
func XrayStop() C.int {
	instanceMu.Lock()
	defer instanceMu.Unlock()

	if instance == nil {
		setLastError(nil)
		return 0
	}

	if err := instance.Close(); err != nil {
		setLastError(fmt.Errorf("core.Close failed: %w", err))
		return 30
	}

	instance = nil
	setLastError(nil)
	return 0
}

//export XrayVersion
func XrayVersion() *C.char {
	return C.CString(core.Version())
}

//export XrayLastError
func XrayLastError() *C.char {
	instanceMu.Lock()
	defer instanceMu.Unlock()
	return C.CString(lastErr)
}

//export XrayFreeString
func XrayFreeString(value *C.char) {
	if value == nil {
		return
	}
	C.free(unsafe.Pointer(value))
}

func main() {}
