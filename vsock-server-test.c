// Simple VSOCK server to simulate NixOS-WSL systemd-shim
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <linux/vm_sockets.h>
#include <errno.h>

#define PLUGIN_PORT 5001
#define VMADDR_CID_ANY 0xFFFFFFFF

int main() {
    printf("VSOCK Server Test - Simulating NixOS-WSL systemd-shim\n");
    printf("=====================================================\n\n");
    
    // Create VSOCK socket
    int server_sock = socket(AF_VSOCK, SOCK_STREAM, 0);
    if (server_sock < 0) {
        perror("Failed to create VSOCK socket");
        return 1;
    }
    
    // Set up server address
    struct sockaddr_vm addr = {
        .svm_family = AF_VSOCK,
        .svm_port = PLUGIN_PORT,
        .svm_cid = VMADDR_CID_ANY,
    };
    
    // Bind to port 5001
    if (bind(server_sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("Failed to bind VSOCK socket");
        close(server_sock);
        return 1;
    }
    
    // Listen for connections
    if (listen(server_sock, 1) < 0) {
        perror("Failed to listen on VSOCK socket");
        close(server_sock);
        return 1;
    }
    
    printf("✅ VSOCK server listening on port %d\n", PLUGIN_PORT);
    printf("⏳ Waiting for plugin connection (timeout: 10 seconds)...\n\n");
    
    // Set timeout
    struct timeval tv = { .tv_sec = 10, .tv_usec = 0 };
    setsockopt(server_sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    
    // Accept connection
    int client_sock = accept(server_sock, NULL, NULL);
    if (client_sock < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            printf("⏰ Timeout - no plugin connected\n");
        } else {
            perror("Accept failed");
        }
        close(server_sock);
        return 1;
    }
    
    printf("🔗 Plugin connected!\n\n");
    
    // Read the test configuration
    FILE *config_file = fopen("/etc/nixos-wsl-plugin.ini", "r");
    if (!config_file) {
        printf("❌ Could not read /etc/nixos-wsl-plugin.ini\n");
        close(client_sock);
        close(server_sock);
        return 1;
    }
    
    // Read configuration content
    char config_buffer[4096];
    size_t config_size = fread(config_buffer, 1, sizeof(config_buffer) - 1, config_file);
    fclose(config_file);
    config_buffer[config_size] = '\0';
    
    printf("📤 Sending configuration (%zu bytes):\n", config_size);
    printf("---\n%s---\n", config_buffer);
    
    // Send configuration to plugin
    if (send(client_sock, config_buffer, config_size, 0) < 0) {
        perror("Failed to send configuration");
        close(client_sock);
        close(server_sock);
        return 1;
    }
    
    printf("✅ Configuration sent\n");
    printf("⏳ Waiting for plugin response...\n\n");
    
    // Receive response
    char response_buffer[4096];
    ssize_t received = recv(client_sock, response_buffer, sizeof(response_buffer) - 1, 0);
    if (received <= 0) {
        printf("❌ Failed to receive response\n");
        close(client_sock);
        close(server_sock);
        return 1;
    }
    
    response_buffer[received] = '\0';
    printf("📥 Received response (%zd bytes):\n", received);
    printf("---\n%s\n---\n\n", response_buffer);
    
    // Check if plugin is ready
    if (strncmp(response_buffer, "STATUS ready", 12) == 0) {
        printf("✅ Plugin reports ready!\n");
    } else {
        printf("⚠️  Plugin not ready: %s\n", response_buffer);
    }
    
    close(client_sock);
    close(server_sock);
    
    printf("\n🎉 VSOCK communication test completed!\n");
    return 0;
}