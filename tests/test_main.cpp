// Main entry point for unit tests
#include "gtest/gtest.h"
#include <iostream>

int main(int argc, char** argv) {
    std::cout << "=== WSL Plugin Unit Tests ===" << std::endl;
    std::cout << "Testing INI parser and core functionality" << std::endl;
    std::cout << std::endl;
    
    // Initialize Google Test
    ::testing::InitGoogleTest(&argc, argv);
    
    // Run all tests
    int result = RUN_ALL_TESTS();
    
    std::cout << std::endl;
    std::cout << "=== Test Run Complete ===" << std::endl;
    
    return result;
}