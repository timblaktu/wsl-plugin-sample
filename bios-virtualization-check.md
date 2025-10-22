# Lenovo Laptop BIOS Virtualization Settings Verification

## Pre-Reboot Checklist
- Save all work in open applications
- Ensure this document path is noted: `/home/tim/src/wsl-plugin-sample/CONTAINER-DEBUGGING.md`
- Repository: wsl-plugin-sample (branch: nixdev)

## BIOS Access Instructions for Lenovo Laptops

### Method 1: Traditional F-Key Access
1. **Completely shut down** the laptop (not restart)
2. **Power on** and immediately press **F1** or **F2** repeatedly
3. If that fails, try **F12** for boot menu, then select BIOS/UEFI setup

### Method 2: Windows Advanced Startup (if F-keys don't work)
1. Hold **Shift** while clicking **Restart** in Windows
2. Choose **Troubleshoot** → **Advanced Options** → **UEFI Firmware Settings**
3. Click **Restart** to enter BIOS

## Critical BIOS Settings to Verify

### Primary Virtualization Settings
Look for these settings (names may vary by BIOS version):

#### 1. Intel VT-x / AMD-V (CPU Virtualization)
- **Location**: Usually under **Security** → **Virtualization** or **Advanced** → **CPU Configuration**
- **Setting Names**:
  - "Intel VT-x Technology" (Intel CPUs)
  - "Intel Virtualization Technology" 
  - "SVM Mode" (AMD CPUs)
  - "Virtualization Technology"
- **Required**: **ENABLED**

#### 2. Intel VT-d / AMD IOMMU (Directed I/O Virtualization)
- **Location**: Same section as VT-x
- **Setting Names**:
  - "Intel VT-d Technology" (Intel CPUs)
  - "VT-d Feature"
  - "IOMMU" (AMD CPUs)
  - "Directed I/O"
- **Required**: **ENABLED** (needed for device passthrough and Hyper-V)

#### 3. Trusted Platform Module (TPM)
- **Location**: **Security** → **TPM** or **Security** → **Trusted Computing**
- **Setting Names**:
  - "TPM Device"
  - "TPM 2.0 Device" 
  - "Security Chip"
- **Required**: **ENABLED** (needed for Windows 11 and VBS)

#### 4. Secure Boot Settings
- **Location**: **Security** → **Secure Boot** or **Boot** → **Secure Boot**
- **Setting Names**:
  - "Secure Boot"
  - "Secure Boot Control"
- **Status**: Check if **ENABLED** (affects virtualization features)

### Lenovo-Specific Settings
Some Lenovo laptops have additional virtualization-related settings:

#### 5. Windows UEFI Firmware Update
- **Location**: **Security** → **UEFI BIOS Update**
- **Check**: Ensure firmware update capability is enabled

#### 6. Intel TXT (Trusted Execution Technology)
- **Location**: **Security** → **Intel TXT** 
- **Setting**: May need to be **ENABLED** for advanced Hyper-V features

## Documentation Template
When you return from BIOS, record findings in this format:

```
=== BIOS VERIFICATION RESULTS ===
Laptop Model: [Fill in exact model]
BIOS Version: [Fill in version/date]

Intel VT-x Technology: [ENABLED/DISABLED]
Intel VT-d Technology: [ENABLED/DISABLED]  
TPM Device: [ENABLED/DISABLED/VERSION]
Secure Boot: [ENABLED/DISABLED]
Intel TXT: [ENABLED/DISABLED/NOT_FOUND]

Additional Notes:
- [Any other relevant settings found]
- [Any settings that were changed]
- [Any settings that couldn't be found]
```

## Expected Results Based on Current System Status

Given that your system shows:
- "A hypervisor has been detected"
- "Virtualization-based security: Running"
- Full Hyper-V feature enabled

**We expect to find**:
- ✅ Intel VT-x: ENABLED
- ✅ Intel VT-d: ENABLED  
- ✅ TPM: ENABLED
- ✅ Secure Boot: Likely ENABLED

**If VT-x shows as DISABLED**, this would explain the WMI false negative while still allowing basic hypervisor functionality through firmware virtualization.

## Post-BIOS Actions
1. Save BIOS settings if any changes were made
2. Boot back to Windows
3. Update the working document with findings
4. Proceed with Docker Desktop installation planning

## Next Chat Context
After BIOS verification, the next chat should continue with:
- Updated virtualization architecture understanding
- BIOS verification results integrated into analysis
- Refined Docker Desktop installation approach based on hardware confirmation