// Simple INI parsing test without Windows APIs
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <map>

struct TestDisk {
    std::string uuid;
    std::string label;
};

struct TestVhdx {
    std::string path;
    int sizeGB;
    std::string filesystem;
};

struct TestResults {
    std::vector<TestDisk> bareDisks;
    std::vector<TestVhdx> vhdxs;
};

TestResults parseIniSimple(const std::string& content) {
    TestResults results;
    std::istringstream stream(content);
    std::string line;
    std::string currentSection;
    
    TestDisk currentDisk;
    TestVhdx currentVhdx;
    bool inBareDisk = false;
    bool inVhdx = false;
    
    while (std::getline(stream, line)) {
        // Trim whitespace
        size_t start = line.find_first_not_of(" \t\r\n");
        if (start == std::string::npos) continue;
        size_t end = line.find_last_not_of(" \t\r\n");
        line = line.substr(start, end - start + 1);
        
        // Skip empty lines and comments
        if (line.empty() || line[0] == '#' || line[0] == ';') continue;
        
        // Check for section headers
        if (line[0] == '[') {
            // Save previous section
            if (inBareDisk && !currentDisk.uuid.empty()) {
                results.bareDisks.push_back(currentDisk);
            }
            if (inVhdx && !currentVhdx.path.empty()) {
                results.vhdxs.push_back(currentVhdx);
            }
            
            size_t end = line.find(']');
            if (end == std::string::npos) continue;
            
            currentSection = line.substr(1, end - 1);
            
            // Reset state
            inBareDisk = currentSection.find("bare_disk_") == 0;
            inVhdx = currentSection.find("vhdx_") == 0;
            
            if (inBareDisk) {
                currentDisk = TestDisk();
            }
            if (inVhdx) {
                currentVhdx = TestVhdx();
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
        
        if (inBareDisk) {
            if (key == "uuid") {
                currentDisk.uuid = value;
            } else if (key == "label") {
                currentDisk.label = value;
            }
        } else if (inVhdx) {
            if (key == "path") {
                currentVhdx.path = value;
            } else if (key == "size_gb") {
                try {
                    currentVhdx.sizeGB = std::stoi(value);
                } catch (const std::exception&) {
                    currentVhdx.sizeGB = 0;
                }
            } else if (key == "filesystem") {
                currentVhdx.filesystem = value;
            }
        }
    }
    
    // Save final section
    if (inBareDisk && !currentDisk.uuid.empty()) {
        results.bareDisks.push_back(currentDisk);
    }
    if (inVhdx && !currentVhdx.path.empty()) {
        results.vhdxs.push_back(currentVhdx);
    }
    
    return results;
}

int main() {
    std::cout << "Simple INI Parser Test\n";
    std::cout << "=====================\n\n";
    
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
    
    std::cout << "Parsing test-config.ini...\n\n";
    
    // Parse the INI content
    TestResults results = parseIniSimple(iniContent);
    
    // Display results
    std::cout << "Results:\n";
    std::cout << "========\n\n";
    
    std::cout << "Bare Disks (" << results.bareDisks.size() << "):\n";
    for (size_t i = 0; i < results.bareDisks.size(); ++i) {
        std::cout << "  [" << (i+1) << "] UUID: " << results.bareDisks[i].uuid << "\n";
        std::cout << "      Label: " << results.bareDisks[i].label << "\n\n";
    }
    
    std::cout << "VHDX Configurations (" << results.vhdxs.size() << "):\n";
    for (size_t i = 0; i < results.vhdxs.size(); ++i) {
        std::cout << "  [" << (i+1) << "] Path: " << results.vhdxs[i].path << "\n";
        std::cout << "      Size: " << results.vhdxs[i].sizeGB << " GB\n";
        std::cout << "      Filesystem: " << results.vhdxs[i].filesystem << "\n\n";
    }
    
    // Validation
    bool success = true;
    if (results.bareDisks.size() != 2) {
        std::cout << "❌ Expected 2 bare disks, got " << results.bareDisks.size() << "\n";
        success = false;
    }
    if (results.vhdxs.size() != 2) {
        std::cout << "❌ Expected 2 VHDX configs, got " << results.vhdxs.size() << "\n";
        success = false;
    }
    
    if (success) {
        std::cout << "✅ Test passed - INI parsing working correctly!\n";
        return 0;
    } else {
        std::cout << "❌ Test failed - INI parsing issues detected\n";
        return 1;
    }
}