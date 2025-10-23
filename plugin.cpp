// WSL Plugin for NixOS-WSL Disk Management

// Define target Windows version before any includes
#include <SDKDDKVer.h>

// Minimize Windows header scope to reduce conflicts
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

// Critical: winsock2.h MUST come before windows.h
#include <winsock2.h>
#include <windows.h>

// Now include specific Windows SDK headers in logical groups
// Storage and disk management - define GUID constants in this compilation unit
#define INITGUID
#include <virtdisk.h>
#undef INITGUID
#include <setupapi.h>
#include <winioctl.h>
// Note: ntddstor.h is often already included via winioctl.h
// Only include it explicitly if you need definitions not in winioctl.h

// COM and WMI
#include <comdef.h>
#include <wbemidl.h>

// Hyper-V sockets
#include <hvsocket.h>

// Standard library (these should come last)
#include <string>
#include <vector>
#include <sstream>
#include <fstream>
#include <codecvt>
#include <locale>

// WSL Plugin API (should come after Windows headers)
#include "WslPluginApi.h"

#pragma comment(lib, "wbemuuid.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")
#pragma comment(lib, "virtdisk.lib")
#pragma comment(lib, "setupapi.lib")

// Service GUID for port 5001
// Format: 00001389-facb-11e6-bd58-64006a7986d3 where 0x1389 = 5001
const GUID ServiceGuid5001 = {
    0x00001389, 0xfacb, 0x11e6, 
    {0xbd, 0x58, 0x64, 0x00, 0x6a, 0x79, 0x86, 0xd3}
};

// Global variables
std::ofstream g_logfile;
const WSLPluginAPIV1* g_api = nullptr;

// Data structures for disk requirements
struct BareDisk {
    std::wstring uuid;
    std::wstring label;
};

struct VhdxConfig {
    std::wstring path;
    DWORD sizeGB;
    std::wstring filesystem;
};

struct DiskRequirements {
    std::vector<BareDisk> bareDisks;
    std::vector<VhdxConfig> vhdxs;
};

struct ValidationResult {
    bool allReady;
    std::wstring message;
};

// Helper function to log messages
void LogMessage(const std::string& message) {
    if (g_logfile.is_open()) {
        g_logfile << message << std::endl;
        g_logfile.flush();
    }
}

// Get VM GUID for a WSL distribution using WMI (simplified version)
GUID GetVmGuidForDistribution(PCWSTR distributionName) {
    GUID vmGuid = {0};
    HRESULT hres;
    
    LogMessage("Querying WMI for VM GUID of distribution: " + 
               std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(distributionName));
    
    // Initialize COM
    hres = CoInitializeEx(0, COINIT_MULTITHREADED);
    if (FAILED(hres) && hres != RPC_E_CHANGED_MODE) {
        LogMessage("Failed to initialize COM: " + std::to_string(hres));
        return vmGuid;
    }
    
    // WMI Query Implementation for Hyper-V VM GUID discovery
    IWbemLocator* pWbemLocator = nullptr;
    IWbemServices* pWbemServices = nullptr;
    
    try {
        // Create WMI locator
        hres = CoCreateInstance(CLSID_WbemLocator, 0, CLSCTX_INPROC_SERVER, IID_IWbemLocator, (LPVOID*)&pWbemLocator);
        if (FAILED(hres)) {
            LogMessage("Failed to create WMI locator: " + std::to_string(hres));
            CoUninitialize();
            return vmGuid;
        }
        
        // Connect to root\virtualization\v2 namespace
        BSTR namespace_path = SysAllocString(L"ROOT\\virtualization\\v2");
        hres = pWbemLocator->ConnectServer(namespace_path, nullptr, nullptr, 0, NULL, 0, 0, &pWbemServices);
        SysFreeString(namespace_path);
        
        if (FAILED(hres)) {
            LogMessage("Failed to connect to Hyper-V WMI namespace: " + std::to_string(hres));
            pWbemLocator->Release();
            CoUninitialize();
            return vmGuid;
        }
        
        // Set security levels
        hres = CoSetProxyBlanket(pWbemServices, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE, nullptr, 
                                RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE);
        if (FAILED(hres)) {
            LogMessage("Warning: Could not set proxy blanket: " + std::to_string(hres));
        }
        
        // Query for VM with matching ElementName
        std::wstring query = L"SELECT Name FROM Msvm_ComputerSystem WHERE Caption = 'Virtual Machine' AND ElementName = '";
        std::wstring wDistName(distributionName);
        query += wDistName + L"'";
        
        BSTR wql = SysAllocString(L"WQL");
        BSTR queryStr = SysAllocString(query.c_str());
        
        IEnumWbemClassObject* pEnumerator = nullptr;
        hres = pWbemServices->ExecQuery(wql, queryStr, WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY, 
                                       nullptr, &pEnumerator);
        
        SysFreeString(wql);
        SysFreeString(queryStr);
        
        if (FAILED(hres)) {
            LogMessage("WMI query failed: " + std::to_string(hres));
        } else {
            IWbemClassObject* pclsObj = nullptr;
            ULONG uReturn = 0;
            
            hres = pEnumerator->Next(WBEM_INFINITE, 1, &pclsObj, &uReturn);
            if (SUCCEEDED(hres) && uReturn == 1) {
                VARIANT vtProp;
                VariantInit(&vtProp);
                
                hres = pclsObj->Get(L"Name", 0, &vtProp, 0, 0);
                if (SUCCEEDED(hres) && vtProp.vt == VT_BSTR) {
                    std::wstring guidStr(vtProp.bstrVal);
                    std::string guidStrNarrow(guidStr.begin(), guidStr.end());
                    LogMessage("Found VM GUID: " + guidStrNarrow);
                    
                    // Convert string to GUID
                    if (CLSIDFromString(vtProp.bstrVal, &vmGuid) == NOERROR) {
                        LogMessage("Successfully parsed VM GUID");
                    } else {
                        LogMessage("Failed to parse VM GUID string");
                        vmGuid = GUID_NULL;
                    }
                } else {
                    LogMessage("Failed to get VM Name property");
                }
                
                VariantClear(&vtProp);
                pclsObj->Release();
            } else {
                LogMessage("No matching VM found for distribution: " + 
                          std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(distributionName));
            }
            
            pEnumerator->Release();
        }
        
        pWbemServices->Release();
        pWbemLocator->Release();
        
    } catch (...) {
        LogMessage("Exception in WMI query");
        if (pWbemServices) pWbemServices->Release();
        if (pWbemLocator) pWbemLocator->Release();
    }
    
    CoUninitialize();
    return vmGuid;
}

// Parse INI configuration received from shim
DiskRequirements ParseIniConfig(const std::string& iniContent) {
    DiskRequirements reqs;
    std::istringstream stream(iniContent);
    std::string line;
    std::string currentSection;
    
    BareDisk currentBareDisk;
    VhdxConfig currentVhdx;
    bool inBareDisk = false;
    bool inVhdx = false;
    
    LogMessage("Parsing INI configuration");
    
    while (std::getline(stream, line)) {
        // Trim whitespace
        line.erase(0, line.find_first_not_of(" \t\r\n"));
        line.erase(line.find_last_not_of(" \t\r\n") + 1);
        
        // Skip empty lines and comments
        if (line.empty() || line[0] == '#' || line[0] == ';') continue;
        
        // Check for section headers
        if (line[0] == '[') {
            // Save previous section if applicable
            if (inBareDisk && !currentBareDisk.uuid.empty()) {
                reqs.bareDisks.push_back(currentBareDisk);
                LogMessage("Added bare disk with UUID");
            }
            if (inVhdx && !currentVhdx.path.empty()) {
                reqs.vhdxs.push_back(currentVhdx);
                LogMessage("Added VHDX configuration");
            }
            
            size_t end = line.find(']');
            if (end == std::string::npos) continue;
            
            currentSection = line.substr(1, end - 1);
            
            // Reset state
            inBareDisk = currentSection.find("bare_disk_") == 0;
            inVhdx = currentSection.find("vhdx_") == 0;
            
            if (inBareDisk) {
                currentBareDisk = BareDisk();
            }
            if (inVhdx) {
                currentVhdx = VhdxConfig();
            }
            
            continue;
        }
        
        // Parse key-value pairs
        size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        
        std::string key = line.substr(0, eq);
        std::string value = line.substr(eq + 1);
        
        // Trim key and value
        key.erase(0, key.find_first_not_of(" \t"));
        key.erase(key.find_last_not_of(" \t") + 1);
        value.erase(0, value.find_first_not_of(" \t"));
        value.erase(value.find_last_not_of(" \t") + 1);
        
        // Convert to wide string using proper UTF-8 decoding
        int wideSize = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, NULL, 0);
        std::wstring wideValue(wideSize, 0);
        MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, &wideValue[0], wideSize);
        wideValue.resize(wideSize - 1); // Remove null terminator
        
        if (inBareDisk) {
            if (key == "uuid") {
                currentBareDisk.uuid = wideValue;
            } else if (key == "label") {
                currentBareDisk.label = wideValue;
            }
        } else if (inVhdx) {
            if (key == "path") {
                currentVhdx.path = wideValue;
            } else if (key == "size_gb") {
                currentVhdx.sizeGB = std::stoul(value);
            } else if (key == "filesystem") {
                currentVhdx.filesystem = wideValue;
            }
        }
    }
    
    // Save final section
    if (inBareDisk && !currentBareDisk.uuid.empty()) {
        reqs.bareDisks.push_back(currentBareDisk);
    }
    if (inVhdx && !currentVhdx.path.empty()) {
        reqs.vhdxs.push_back(currentVhdx);
    }
    
    LogMessage("Parsed " + std::to_string(reqs.bareDisks.size()) + " bare disks and " + 
               std::to_string(reqs.vhdxs.size()) + " VHDX configurations");
    
    return reqs;
}

// Check if bare disk is present (simplified implementation)
bool IsDiskPresent(const std::wstring& uuid) {
    // Windows Disk Management API implementation for disk enumeration
    LogMessage("Checking for disk with UUID: " + 
               std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(uuid));
    
    // Get device information set for disk devices
    HDEVINFO hDevInfo = SetupDiGetClassDevs(&GUID_DEVINTERFACE_DISK, nullptr, nullptr, 
                                           DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (hDevInfo == INVALID_HANDLE_VALUE) {
        LogMessage("Failed to get disk device information set");
        return false;
    }
    
    SP_DEVICE_INTERFACE_DATA deviceInterfaceData;
    deviceInterfaceData.cbSize = sizeof(SP_DEVICE_INTERFACE_DATA);
    
    // Enumerate through all disk devices
    for (DWORD deviceIndex = 0; 
         SetupDiEnumDeviceInterfaces(hDevInfo, nullptr, &GUID_DEVINTERFACE_DISK, deviceIndex, &deviceInterfaceData);
         deviceIndex++) {
        
        // Get required buffer size for device interface detail
        DWORD requiredSize = 0;
        SetupDiGetDeviceInterfaceDetail(hDevInfo, &deviceInterfaceData, nullptr, 0, &requiredSize, nullptr);
        
        if (GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
            continue;
        }
        
        // Allocate buffer for device interface detail
        PSP_DEVICE_INTERFACE_DETAIL_DATA deviceInterfaceDetailData = 
            (PSP_DEVICE_INTERFACE_DETAIL_DATA)malloc(requiredSize);
        if (!deviceInterfaceDetailData) {
            continue;
        }
        
        deviceInterfaceDetailData->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA);
        
        // Get device interface detail
        if (SetupDiGetDeviceInterfaceDetail(hDevInfo, &deviceInterfaceData, deviceInterfaceDetailData, 
                                          requiredSize, nullptr, nullptr)) {
            
            // Open handle to the disk device
            HANDLE hDevice = CreateFile(deviceInterfaceDetailData->DevicePath, 0, 
                                      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, 
                                      OPEN_EXISTING, 0, nullptr);
            
            if (hDevice != INVALID_HANDLE_VALUE) {
                // Query storage device descriptor to get device information
                STORAGE_PROPERTY_QUERY query;
                query.PropertyId = StorageDeviceProperty;
                query.QueryType = PropertyStandardQuery;
                
                STORAGE_DESCRIPTOR_HEADER header;
                DWORD bytesReturned;
                
                if (DeviceIoControl(hDevice, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query),
                                  &header, sizeof(header), &bytesReturned, nullptr)) {
                    
                    // Allocate buffer for full device descriptor
                    PSTORAGE_DEVICE_DESCRIPTOR deviceDescriptor = 
                        (PSTORAGE_DEVICE_DESCRIPTOR)malloc(header.Size);
                    
                    if (deviceDescriptor && 
                        DeviceIoControl(hDevice, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query),
                                      deviceDescriptor, header.Size, &bytesReturned, nullptr)) {
                        
                        // Get vendor and product ID to construct UUID check
                        std::string vendorId, productId;
                        if (deviceDescriptor->VendorIdOffset > 0) {
                            vendorId = (char*)deviceDescriptor + deviceDescriptor->VendorIdOffset;
                        }
                        if (deviceDescriptor->ProductIdOffset > 0) {
                            productId = (char*)deviceDescriptor + deviceDescriptor->ProductIdOffset;
                        }
                        
                        // Note: This is a simplified UUID check. Real implementation would
                        // query the disk's partition table UUID using IOCTL_DISK_GET_DRIVE_LAYOUT_EX
                        std::string diskInfo = vendorId + " " + productId;
                        std::wstring wDiskInfo(diskInfo.begin(), diskInfo.end());
                        
                        LogMessage("Found disk: " + diskInfo);
                        
                        // For now, check if the UUID is contained in the disk path
                        std::wstring devicePath(deviceInterfaceDetailData->DevicePath);
                        if (devicePath.find(uuid) != std::wstring::npos) {
                            LogMessage("Found matching disk by UUID");
                            free(deviceDescriptor);
                            CloseHandle(hDevice);
                            free(deviceInterfaceDetailData);
                            SetupDiDestroyDeviceInfoList(hDevInfo);
                            return true;
                        }
                    }
                    
                    if (deviceDescriptor) {
                        free(deviceDescriptor);
                    }
                }
                
                CloseHandle(hDevice);
            }
        }
        
        free(deviceInterfaceDetailData);
    }
    
    SetupDiDestroyDeviceInfoList(hDevInfo);
    LogMessage("No disk found with matching UUID");
    return false;
}

// Check if VHDX file exists
bool VhdxExists(const std::wstring& path) {
    DWORD attrib = GetFileAttributesW(path.c_str());
    return (attrib != INVALID_FILE_ATTRIBUTES && !(attrib & FILE_ATTRIBUTE_DIRECTORY));
}

// Create VHDX file using Windows Virtual Disk Service API
bool CreateVhdxFile(const std::wstring& path, DWORD sizeGB, const std::wstring& filesystem) {
    LogMessage("Creating VHDX at: " + 
               std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(path) + 
               " with size " + std::to_string(sizeGB) + "GB");
    
    // Virtual disk parameters
    VIRTUAL_STORAGE_TYPE storageType;
    storageType.DeviceId = VIRTUAL_STORAGE_TYPE_DEVICE_VHDX;
    storageType.VendorId = VIRTUAL_STORAGE_TYPE_VENDOR_MICROSOFT;
    
    CREATE_VIRTUAL_DISK_PARAMETERS createParams;
    ZeroMemory(&createParams, sizeof(createParams));
    createParams.Version = CREATE_VIRTUAL_DISK_VERSION_2;
    createParams.Version2.MaximumSize = (ULONGLONG)sizeGB * 1024 * 1024 * 1024; // Convert GB to bytes
    createParams.Version2.BlockSizeInBytes = 0; // Use default block size
    createParams.Version2.SectorSizeInBytes = 0; // Use default sector size
    
    HANDLE vhdHandle = nullptr;
    DWORD result = CreateVirtualDisk(
        &storageType,
        path.c_str(),
        VIRTUAL_DISK_ACCESS_NONE,
        nullptr,
        CREATE_VIRTUAL_DISK_FLAG_NONE,
        0,
        &createParams,
        nullptr,
        &vhdHandle
    );
    
    if (result != ERROR_SUCCESS) {
        LogMessage("Failed to create VHDX file: " + std::to_string(result));
        return false;
    }
    
    LogMessage("Successfully created VHDX file");
    
    // Attach the virtual disk
    ATTACH_VIRTUAL_DISK_PARAMETERS attachParams;
    ZeroMemory(&attachParams, sizeof(attachParams));
    attachParams.Version = ATTACH_VIRTUAL_DISK_VERSION_1;
    
    result = AttachVirtualDisk(
        vhdHandle,
        nullptr,
        ATTACH_VIRTUAL_DISK_FLAG_PERMANENT_LIFETIME,
        0,
        &attachParams,
        nullptr
    );
    
    if (result != ERROR_SUCCESS) {
        LogMessage("Failed to attach VHDX file: " + std::to_string(result));
        CloseHandle(vhdHandle);
        return false;
    }
    
    LogMessage("Successfully attached VHDX file");
    
    // Get the physical disk path for formatting
    WCHAR diskPath[MAX_PATH];
    ULONG diskPathSize = sizeof(diskPath);
    
    result = GetVirtualDiskPhysicalPath(vhdHandle, &diskPathSize, diskPath);
    if (result == ERROR_SUCCESS) {
        LogMessage("VHDX physical path: " + 
                   std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(diskPath));
        
        // Note: Disk formatting would require additional APIs
        // For now, we just log that the disk is ready for formatting
        LogMessage("VHDX created and attached - ready for formatting with " + 
                   std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(filesystem));
    } else {
        LogMessage("Warning: Could not get VHDX physical path: " + std::to_string(result));
    }
    
    CloseHandle(vhdHandle);
    return true;
}

// Check if VHDX is attached (simplified implementation)
bool IsVhdxAttached(const std::wstring& path) {
    // In a real implementation, this would query WSL for attached VHDXs
    LogMessage("Checking if VHDX is attached: " + 
               std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(path));
    return false;
}

// Validate and mount all disks
ValidationResult ValidateAndMountDisks(const std::wstring& distroName, const DiskRequirements& reqs) {
    ValidationResult result;
    result.allReady = true;
    
    LogMessage("Validating disk requirements for " + 
               std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(distroName));
    
    for (const auto& disk : reqs.bareDisks) {
        if (!IsDiskPresent(disk.uuid)) {
            result.allReady = false;
            result.message += L"Disk " + disk.uuid + L" not found. ";
        }
    }
    
    for (const auto& vhdx : reqs.vhdxs) {
        if (!VhdxExists(vhdx.path)) {
            LogMessage("VHDX does not exist, creating: " + 
                      std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(vhdx.path));
            CreateVhdxFile(vhdx.path, vhdx.sizeGB, vhdx.filesystem);
        }
        
        if (!IsVhdxAttached(vhdx.path)) {
            result.allReady = false;
            result.message += L"VHDX " + vhdx.path + L" needs mounting. ";
        }
    }
    
    if (result.allReady) {
        result.message = L"All disks ready";
    }
    
    return result;
}

// Read from socket helper
std::vector<char> ReadFromSocket(SOCKET socket) {
    int result = 0;
    int offset = 0;
    
    std::vector<char> content(1024);
    while ((result = recv(socket, content.data() + offset, 1024, 0)) > 0) {
        offset += result;
        content.resize(offset + 1024);
    }
    
    content.resize(offset);
    return content;
}

// OnDistributionStarted callback - main implementation
HRESULT OnDistroStarted(const WSLSessionInformation* Session, const WSLDistributionInformation* Distribution) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>, wchar_t> converter;
    std::string distroName = converter.to_bytes(Distribution->Name);
    
    LogMessage("=== DISTRIBUTION STARTED: " + distroName + " ===");
    LogMessage("SessionId: " + std::to_string(Session->SessionId));
    LogMessage("PidNamespace: " + std::to_string(Distribution->PidNamespace));
    LogMessage("InitPid: " + std::to_string(Distribution->InitPid));
    
    try {
        // Check if this is a NixOS distribution
        if (distroName.find("NixOS") == std::string::npos && 
            distroName.find("nixos") == std::string::npos) {
            LogMessage("Not a NixOS distribution, skipping plugin activation");
            return S_OK;
        }
        
        LogMessage("NixOS distribution detected, attempting VSOCK communication");
        
        // Get VM GUID for this distribution
        GUID vmGuid = GetVmGuidForDistribution(Distribution->Name);
        
        // If GUID is null, this might be WSL1 or VM not found
        if (vmGuid.Data1 == 0) {
            LogMessage("No VM GUID found - might be WSL1 or VM not found");
            // For demo purposes, simulate receiving config
            std::string demoConfig = "[version]\nformat=1\n\n[bare_disk_1]\nuuid=test-uuid\nlabel=test-disk\n";
            LogMessage("Demo mode: Using sample configuration");
            
            // Parse configuration
            DiskRequirements reqs = ParseIniConfig(demoConfig);
            
            // Validate and mount disks
            ValidationResult validation = ValidateAndMountDisks(Distribution->Name, reqs);
            
            if (validation.allReady) {
                LogMessage("All disk requirements satisfied");
                return S_OK;
            } else {
                LogMessage("Disk requirements not satisfied");
                return E_FAIL;
            }
        }
        
        // Initialize Winsock
        WSADATA wsaData;
        if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
            LogMessage("Failed to initialize Winsock");
            return S_OK;
        }
        
        /*
         * REAL VSOCK/AF_HYPERV IMPLEMENTATION
         * 
         * This is the production implementation that would be used with MSVC compiler.
         * MinGW cannot compile this because:
         * 1. AF_HYPERV is not defined in MinGW headers (requires Windows SDK)
         * 2. SOCKADDR_HV structure is not available in MinGW
         * 3. HV_PROTOCOL_RAW constant is not defined
         * 
         * To use this code, compile with Visual Studio or MSVC toolchain which includes
         * the full Windows SDK with Hyper-V socket definitions.
         */
        // Create AF_HYPERV socket for VSOCK communication
        SOCKET sock = socket(AF_HYPERV, SOCK_STREAM, HV_PROTOCOL_RAW);
        if (sock == INVALID_SOCKET) {
            LogMessage("Failed to create AF_HYPERV socket: " + std::to_string(WSAGetLastError()));
            WSACleanup();
            return S_OK;
        }
        
        // Set connection timeout (2 seconds)
        DWORD timeout = 2000;
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (const char*)&timeout, sizeof(timeout));
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (const char*)&timeout, sizeof(timeout));
        
        // Construct SOCKADDR_HV for connection
        SOCKADDR_HV addr = {0};
        addr.Family = AF_HYPERV;
        addr.Reserved = 0;
        addr.VmId = vmGuid;
        addr.ServiceId = ServiceGuid5001;  // Port 5001 encoded in GUID
        
        // Try connection with retry logic (up to 3 attempts)
        int connectResult = SOCKET_ERROR;
        for (int attempt = 0; attempt < 3; ++attempt) {
            LogMessage("VSOCK connection attempt " + std::to_string(attempt + 1) + " to port 5001");
            connectResult = connect(sock, (SOCKADDR*)&addr, sizeof(addr));
            
            if (connectResult != SOCKET_ERROR) {
                LogMessage("Successfully connected to systemd-shim via VSOCK");
                break;
            }
            
            int error = WSAGetLastError();
            LogMessage("Connection attempt failed: " + std::to_string(error));
            
            // Don't retry on certain errors
            if (error != WSAECONNREFUSED && error != WSAETIMEDOUT) {
                break;
            }
            
            // Short delay before retry
            Sleep(100);
        }
        
        if (connectResult == SOCKET_ERROR) {
            // Connection failed - distribution doesn't support protocol
            LogMessage("VSOCK connection failed after 3 attempts - distribution may not have listener");
            closesocket(sock);
            WSACleanup();
            return S_OK;
        }
        
        // Receive configuration from shim
        std::vector<char> buffer = ReadFromSocket(sock);
        
        if (buffer.empty()) {
            LogMessage("No data received from systemd-shim");
            closesocket(sock);
            WSACleanup();
            return S_OK;
        }
        
        std::string configContent(buffer.begin(), buffer.end());
        LogMessage("Received " + std::to_string(configContent.size()) + " bytes of configuration");
        
        // Parse configuration
        DiskRequirements reqs = ParseIniConfig(configContent);
        
        // Validate and mount disks
        ValidationResult validation = ValidateAndMountDisks(Distribution->Name, reqs);
        
        // Send response
        std::string response;
        if (validation.allReady) {
            response = "STATUS ready\n";
            LogMessage("Sending STATUS ready to systemd-shim");
        } else {
            // Convert wide string message to UTF-8
            std::string msg = converter.to_bytes(validation.message);
            response = "STATUS notReady\nMESSAGE " + msg + "\n";
            LogMessage("Sending STATUS notReady to systemd-shim");
        }
        
        send(sock, response.c_str(), (int)response.length(), 0);
        
        closesocket(sock);
        WSACleanup();
        
        return validation.allReady ? S_OK : E_FAIL;
        
    } catch (const std::exception& e) {
        LogMessage("Exception occurred in OnDistroStarted: " + std::string(e.what()));
        return E_UNEXPECTED;
    }
}

// Other callbacks (simplified implementations)
HRESULT OnVmStarted(const WSLSessionInformation* Session, const WSLVmCreationSettings* Settings) {
    LogMessage("=== VM STARTED ===");
    LogMessage("SessionId: " + std::to_string(Session->SessionId));
    LogMessage("CustomConfigurationFlags: " + std::to_string(Settings->CustomConfigurationFlags));
    
    // Log custom feature for identification
    LogMessage("CUSTOM: NixOS-WSL Disk Management Plugin Active");
    
    return S_OK;
}

HRESULT OnVmStopping(const WSLSessionInformation* Session) {
    LogMessage("=== VM STOPPING ===");
    LogMessage("SessionId: " + std::to_string(Session->SessionId));
    return S_OK;
}

HRESULT OnDistroStopping(const WSLSessionInformation* Session, const WSLDistributionInformation* Distribution) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>, wchar_t> converter;
    LogMessage("=== DISTRIBUTION STOPPING ===");
    LogMessage("Distribution: " + converter.to_bytes(Distribution->Name));
    return S_OK;
}

HRESULT OnDistroRegistered(const WSLSessionInformation* Session, const WslOfflineDistributionInformation* Distribution) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>, wchar_t> converter;
    LogMessage("=== DISTRIBUTION REGISTERED ===");
    LogMessage("Distribution: " + converter.to_bytes(Distribution->Name));
    LogMessage("CUSTOM: Ready to manage disk requirements for " + converter.to_bytes(Distribution->Name));
    return S_OK;
}

HRESULT OnDistroUnregistered(const WSLSessionInformation* Session, const WslOfflineDistributionInformation* Distribution) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>, wchar_t> converter;
    LogMessage("=== DISTRIBUTION UNREGISTERED ===");
    LogMessage("Distribution: " + converter.to_bytes(Distribution->Name));
    return S_OK;
}

// Entry point called by wslservice when the plugin is loaded
extern "C" __declspec(dllexport) HRESULT WSLPLUGINAPI_ENTRYPOINTV1(const WSLPluginAPIV1* Api, WSLPluginHooksV1* Hooks) {
    // Save the API methods to call them later
    g_api = Api;
    
    // Open log file
    g_logfile.open("C:\\wsl-plugin-nixos.txt");
    if (!g_logfile) {
        return E_ABORT;
    }
    
    LogMessage("=== WSL PLUGIN FOR NIXOS-WSL LOADED ===");
    LogMessage("WSL version: " + std::to_string(Api->Version.Major) + "." + 
               std::to_string(Api->Version.Minor) + "." + 
               std::to_string(Api->Version.Revision));
    LogMessage("Plugin implements VSOCK-based disk management for NixOS-WSL");
    LogMessage("CUSTOM: This plugin manages declarative disk requirements");
    
    // Require WSL >= 2.1.3
    WSL_PLUGIN_REQUIRE_VERSION(2, 1, 3, Api);
    
    // Register the plugin hooks with WSL
    Hooks->OnVMStarted = &OnVmStarted;
    Hooks->OnVMStopping = &OnVmStopping;
    Hooks->OnDistributionStarted = &OnDistroStarted;
    Hooks->OnDistributionStopping = &OnDistroStopping;
    Hooks->OnDistributionRegistered = &OnDistroRegistered;
    Hooks->OnDistributionUnregistered = &OnDistroUnregistered;
    
    LogMessage("Plugin hooks registered successfully");
    
    return S_OK;
}
