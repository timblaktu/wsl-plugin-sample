// Simple test program to validate plugin functionality without WSL installation
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <windows.h>

// Copy the structures from plugin.cpp for testing
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

// Copy the ParseIniConfig function from plugin.cpp
DiskRequirements ParseIniConfig(const std::string& iniContent) {
    DiskRequirements reqs;
    std::istringstream stream(iniContent);
    std::string line;
    std::string currentSection;
    
    BareDisk currentBareDisk;
    VhdxConfig currentVhdx;
    bool inBareDisk = false;
    bool inVhdx = false;
    
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
            }
            if (inVhdx && !currentVhdx.path.empty()) {
                reqs.vhdxs.push_back(currentVhdx);
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
                try {
                    currentVhdx.sizeGB = std::stoul(value);
                } catch (const std::exception&) {
                    currentVhdx.sizeGB = 0; // Default to 0 for invalid values
                }
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
    
    return reqs;
}

// Helper function to convert wstring to string for display
std::string wstring_to_string(const std::wstring& wstr) {
    int size = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, NULL, 0, NULL, NULL);
    std::string str(size, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &str[0], size, NULL, NULL);
    str.resize(size - 1); // Remove null terminator
    return str;
}

int main() {
    std::cout << "WSL Plugin - INI Parsing Test\n";
    std::cout << "=============================\n\n";
    
    // Read test-config.ini file
    std::ifstream file("test-config.ini");
    if (!file.is_open()) {
        std::cout << "Error: Could not open test-config.ini\n";
        return 1;
    }
    
    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string iniContent = buffer.str();
    file.close();
    
    std::cout << "INI Content:\n" << iniContent << "\n\n";
    
    // Parse the INI content
    DiskRequirements reqs = ParseIniConfig(iniContent);
    
    // Display results
    std::cout << "Parsing Results:\n";
    std::cout << "================\n\n";
    
    std::cout << "Bare Disks (" << reqs.bareDisks.size() << "):\n";
    for (size_t i = 0; i < reqs.bareDisks.size(); ++i) {
        std::cout << "  [" << i+1 << "] UUID: " << wstring_to_string(reqs.bareDisks[i].uuid) << "\n";
        std::cout << "      Label: " << wstring_to_string(reqs.bareDisks[i].label) << "\n\n";
    }
    
    std::cout << "VHDX Configurations (" << reqs.vhdxs.size() << "):\n";
    for (size_t i = 0; i < reqs.vhdxs.size(); ++i) {
        std::cout << "  [" << i+1 << "] Path: " << wstring_to_string(reqs.vhdxs[i].path) << "\n";
        std::cout << "      Size: " << reqs.vhdxs[i].sizeGB << " GB\n";
        std::cout << "      Filesystem: " << wstring_to_string(reqs.vhdxs[i].filesystem) << "\n\n";
    }
    
    std::cout << "Test completed successfully!\n";
    return 0;
}