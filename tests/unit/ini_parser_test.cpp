// Unit tests for INI configuration parser
#include "gtest/gtest.h"
#include <windows.h>  // Required for DWORD, CP_UTF8, MultiByteToWideChar
#include <string>
#include <vector>
#include <sstream>
#include <fstream>
#include <codecvt>
#include <locale>
#include <iostream>

// We need to include the structures and function from plugin.cpp
// Since we can't include plugin.cpp directly (it has DLL entry points),
// we'll recreate the essential structures and function for testing

// Data structures from plugin.cpp
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

// Copy of ParseIniConfig function for testing
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

// Helper function to load test fixture
std::string LoadTestFixture(const std::string& filename) {
    std::ifstream file("../tests/fixtures/sample_configs/" + filename);
    if (!file.is_open()) {
        return "";
    }
    
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

// Test class for INI parser
class IniParserTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Setup code if needed
    }
    
    void TearDown() override {
        // Cleanup code if needed  
    }
};

// Test valid configuration parsing
TEST_F(IniParserTest, ValidConfiguration) {
    std::string validIni = LoadTestFixture("valid_config.ini");
    ASSERT_FALSE(validIni.empty()) << "Could not load valid_config.ini fixture";
    
    DiskRequirements result = ParseIniConfig(validIni);
    
    // Should have 2 bare disks
    EXPECT_EQ(result.bareDisks.size(), 2);
    EXPECT_EQ(result.bareDisks[0].uuid, L"e8f7a6b5-1234-5678-9abc-def012345678");
    EXPECT_EQ(result.bareDisks[0].label, L"data-disk");
    EXPECT_EQ(result.bareDisks[1].uuid, L"f9e8b7a6-2345-6789-abcd-ef0123456789");
    EXPECT_EQ(result.bareDisks[1].label, L"backup-disk");
    
    // Should have 2 VHDX configs
    EXPECT_EQ(result.vhdxs.size(), 2);
    EXPECT_EQ(result.vhdxs[0].path, L"D:\\WSL\\data.vhdx");
    EXPECT_EQ(result.vhdxs[0].sizeGB, 100);
    EXPECT_EQ(result.vhdxs[0].filesystem, L"ext4");
    EXPECT_EQ(result.vhdxs[1].path, L"C:\\WSL\\workspace.vhdx");
    EXPECT_EQ(result.vhdxs[1].sizeGB, 50);
    EXPECT_EQ(result.vhdxs[1].filesystem, L"btrfs");
}

// Test malformed configuration handling
TEST_F(IniParserTest, MalformedConfiguration) {
    std::string malformedIni = LoadTestFixture("malformed_config.ini");
    ASSERT_FALSE(malformedIni.empty()) << "Could not load malformed_config.ini fixture";
    
    DiskRequirements result = ParseIniConfig(malformedIni);
    
    // Should handle malformed sections gracefully
    // Only sections with valid closing brackets and non-empty UUIDs should be parsed
    EXPECT_EQ(result.bareDisks.size(), 0); // bare_disk_2 has empty uuid
    EXPECT_EQ(result.vhdxs.size(), 1); // vhdx_1 should parse despite invalid size_gb
    EXPECT_EQ(result.vhdxs[0].path, L"D:\\WSL\\test.vhdx");
    EXPECT_EQ(result.vhdxs[0].sizeGB, 0); // stoul of "invalid_number" should throw, resulting in 0
}

// Test edge cases
TEST_F(IniParserTest, EdgeCases) {
    std::string edgeCaseIni = LoadTestFixture("edge_cases.ini");
    ASSERT_FALSE(edgeCaseIni.empty()) << "Could not load edge_cases.ini fixture";
    
    DiskRequirements result = ParseIniConfig(edgeCaseIni);
    
    // Should handle whitespace and comments properly
    // Note: incomplete_section has no closing bracket so should be ignored
    EXPECT_EQ(result.bareDisks.size(), 3); // bare_disk_1, bare_disk_unicode, and one more valid section
    EXPECT_EQ(result.vhdxs.size(), 1); // vhdx_1
    
    // Check whitespace trimming
    EXPECT_EQ(result.bareDisks[0].uuid, L"e8f7a6b5-1234-5678-9abc-def012345678");
    EXPECT_EQ(result.bareDisks[0].label, L"disk-with-spaces");
    
    // Check path with spaces
    EXPECT_EQ(result.vhdxs[0].path, L"C:\\Path With Spaces\\test.vhdx");
    EXPECT_EQ(result.vhdxs[0].sizeGB, 1);
}

// Test empty configuration
TEST_F(IniParserTest, EmptyConfiguration) {
    std::string emptyIni = "";
    
    DiskRequirements result = ParseIniConfig(emptyIni);
    
    EXPECT_EQ(result.bareDisks.size(), 0);
    EXPECT_EQ(result.vhdxs.size(), 0);
}

// Test configuration with only comments
TEST_F(IniParserTest, OnlyComments) {
    std::string commentsOnlyIni = R"(
# This is a comment
; This is also a comment
# Another comment line
)";
    
    DiskRequirements result = ParseIniConfig(commentsOnlyIni);
    
    EXPECT_EQ(result.bareDisks.size(), 0);
    EXPECT_EQ(result.vhdxs.size(), 0);
}

// Test single bare disk configuration
TEST_F(IniParserTest, SingleBareDisk) {
    std::string singleDiskIni = R"(
[bare_disk_test]
uuid=12345678-1234-1234-1234-123456789abc
label=test-disk
)";
    
    DiskRequirements result = ParseIniConfig(singleDiskIni);
    
    EXPECT_EQ(result.bareDisks.size(), 1);
    EXPECT_EQ(result.vhdxs.size(), 0);
    EXPECT_EQ(result.bareDisks[0].uuid, L"12345678-1234-1234-1234-123456789abc");
    EXPECT_EQ(result.bareDisks[0].label, L"test-disk");
}

// Test single VHDX configuration
TEST_F(IniParserTest, SingleVhdx) {
    std::string singleVhdxIni = R"(
[vhdx_test]
path=C:\Test\single.vhdx
size_gb=25
filesystem=ntfs
)";
    
    DiskRequirements result = ParseIniConfig(singleVhdxIni);
    
    EXPECT_EQ(result.bareDisks.size(), 0);
    EXPECT_EQ(result.vhdxs.size(), 1);
    EXPECT_EQ(result.vhdxs[0].path, L"C:\\Test\\single.vhdx");
    EXPECT_EQ(result.vhdxs[0].sizeGB, 25);
    EXPECT_EQ(result.vhdxs[0].filesystem, L"ntfs");
}