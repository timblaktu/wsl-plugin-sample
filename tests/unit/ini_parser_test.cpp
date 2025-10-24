// Unit tests for INI configuration parser
#include "gtest/gtest.h"
#include <fstream>
#include <iostream>

// Use shared INI parser implementation to avoid code duplication
#include "../../shared/ini_parser.h"

// Helper function to load test fixture with container-aware path resolution
std::string LoadTestFixture(const std::string& filename) {
    // Try multiple possible paths for different build environments
    std::vector<std::string> searchPaths = {
        "../tests/fixtures/sample_configs/",           // Relative from test binary (Linux/WSL)
        "tests/fixtures/sample_configs/",              // Relative from project root
        "C:/work/tests/fixtures/sample_configs/",      // Container absolute path
        "./tests/fixtures/sample_configs/",            // Current directory relative
        "../sample_configs/",                          // Simplified relative
        "sample_configs/"                              // Local directory
    };
    
    for (const auto& basePath : searchPaths) {
        std::string fullPath = basePath + filename;
        std::ifstream file(fullPath);
        if (file.is_open()) {
            std::stringstream buffer;
            buffer << file.rdbuf();
            return buffer.str();
        }
    }
    
    // If no file found, log the attempted paths for debugging
    std::cerr << "LoadTestFixture: Could not find " << filename << " in any of the following paths:" << std::endl;
    for (const auto& path : searchPaths) {
        std::cerr << "  - " << path + filename << std::endl;
    }
    
    return "";
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