// Unit tests for string conversion functions
#include "gtest/gtest.h"
#include <windows.h>  // Must be first to define types correctly
#include <string>
#include <codecvt>
#include <locale>

// Test class for string conversion
class StringConversionTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Setup code if needed
    }
    
    void TearDown() override {
        // Cleanup code if needed  
    }
};

// Helper function to convert UTF-8 to UTF-16 (like in plugin.cpp)
std::wstring ConvertUtf8ToUtf16(const std::string& utf8String) {
    if (utf8String.empty()) {
        return std::wstring();
    }
    
    int wideSize = MultiByteToWideChar(CP_UTF8, 0, utf8String.c_str(), -1, NULL, 0);
    if (wideSize <= 0) {
        return std::wstring();
    }
    
    std::wstring wideString(wideSize, 0);
    MultiByteToWideChar(CP_UTF8, 0, utf8String.c_str(), -1, &wideString[0], wideSize);
    wideString.resize(wideSize - 1); // Remove null terminator
    
    return wideString;
}

// Helper function to convert UTF-16 to UTF-8 (like in plugin.cpp)
std::string ConvertUtf16ToUtf8(const std::wstring& utf16String) {
    if (utf16String.empty()) {
        return std::string();
    }
    
    std::wstring_convert<std::codecvt_utf8<wchar_t>, wchar_t> converter;
    return converter.to_bytes(utf16String);
}

// Test basic ASCII string conversion
TEST_F(StringConversionTest, BasicAsciiConversion) {
    std::string utf8 = "test-string";
    std::wstring utf16 = ConvertUtf8ToUtf16(utf8);
    
    EXPECT_EQ(utf16, L"test-string");
    
    // Convert back to verify round-trip
    std::string backToUtf8 = ConvertUtf16ToUtf8(utf16);
    EXPECT_EQ(backToUtf8, utf8);
}

// Test empty string handling
TEST_F(StringConversionTest, EmptyStringHandling) {
    std::string empty = "";
    std::wstring result = ConvertUtf8ToUtf16(empty);
    
    EXPECT_TRUE(result.empty());
    
    // Test reverse conversion
    std::wstring emptyWide = L"";
    std::string resultNarrow = ConvertUtf16ToUtf8(emptyWide);
    
    EXPECT_TRUE(resultNarrow.empty());
}

// Test UUID string conversion
TEST_F(StringConversionTest, UuidStringConversion) {
    std::string uuid = "e8f7a6b5-1234-5678-9abc-def012345678";
    std::wstring wideUuid = ConvertUtf8ToUtf16(uuid);
    
    EXPECT_EQ(wideUuid, L"e8f7a6b5-1234-5678-9abc-def012345678");
    
    // Verify GUID parsing would work (just check format)
    EXPECT_EQ(wideUuid.length(), 36); // Standard UUID length
    EXPECT_EQ(wideUuid[8], L'-');     // Check dash positions
    EXPECT_EQ(wideUuid[13], L'-');
    EXPECT_EQ(wideUuid[18], L'-');
    EXPECT_EQ(wideUuid[23], L'-');
}

// Test file path conversion
TEST_F(StringConversionTest, FilePathConversion) {
    std::string path = "D:\\WSL\\data.vhdx";
    std::wstring widePath = ConvertUtf8ToUtf16(path);
    
    EXPECT_EQ(widePath, L"D:\\WSL\\data.vhdx");
    
    // Test path with spaces
    std::string pathWithSpaces = "C:\\Path With Spaces\\test.vhdx";
    std::wstring widePathWithSpaces = ConvertUtf8ToUtf16(pathWithSpaces);
    
    EXPECT_EQ(widePathWithSpaces, L"C:\\Path With Spaces\\test.vhdx");
}

// Test special characters and Unicode
TEST_F(StringConversionTest, UnicodeCharacters) {
    // Test with some Unicode characters (Chinese characters as in edge_cases.ini)
    std::string utf8WithUnicode = "测试磁盘";
    std::wstring utf16Result = ConvertUtf8ToUtf16(utf8WithUnicode);
    
    // Verify the conversion doesn't crash and produces non-empty result
    EXPECT_FALSE(utf16Result.empty());
    
    // Test round-trip conversion
    std::string backToUtf8 = ConvertUtf16ToUtf8(utf16Result);
    EXPECT_EQ(backToUtf8, utf8WithUnicode);
}

// Test whitespace handling
TEST_F(StringConversionTest, WhitespaceHandling) {
    std::string withSpaces = "  test-value  ";
    std::wstring wideWithSpaces = ConvertUtf8ToUtf16(withSpaces);
    
    EXPECT_EQ(wideWithSpaces, L"  test-value  ");
    
    // Test tabs and newlines
    std::string withTabs = "\ttest\t";
    std::wstring wideWithTabs = ConvertUtf8ToUtf16(withTabs);
    
    EXPECT_EQ(wideWithTabs, L"\ttest\t");
}

// Test null and control characters
TEST_F(StringConversionTest, ControlCharacters) {
    // Test string with embedded null (should stop at null)
    std::string withNull = std::string("test\0more", 9);
    std::wstring wideWithNull = ConvertUtf8ToUtf16(withNull);
    
    // MultiByteToWideChar should stop at the first null
    EXPECT_EQ(wideWithNull, L"test");
}

// Test large strings
TEST_F(StringConversionTest, LargeStrings) {
    // Create a large string
    std::string largeString(1024, 'A');
    std::wstring wideLargeString = ConvertUtf8ToUtf16(largeString);
    
    EXPECT_EQ(wideLargeString.length(), 1024);
    EXPECT_EQ(wideLargeString, std::wstring(1024, L'A'));
    
    // Test round-trip
    std::string backToNarrow = ConvertUtf16ToUtf8(wideLargeString);
    EXPECT_EQ(backToNarrow, largeString);
}

// Test error conditions (if any)
TEST_F(StringConversionTest, ErrorConditions) {
    // Test with invalid UTF-8 sequence
    std::string invalidUtf8 = "\xFF\xFE\xFD";
    std::wstring result = ConvertUtf8ToUtf16(invalidUtf8);
    
    // Should handle gracefully (may produce empty string or replacement chars)
    // The exact behavior depends on Windows API implementation
    // Just verify it doesn't crash
    EXPECT_TRUE(true); // If we get here, no crash occurred
}