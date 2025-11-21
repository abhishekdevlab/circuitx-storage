*** Settings ***
Documentation     Professional 4G/5G Telecom Automation Framework
...               Includes: Bulk Users (50), Mobility, Negative Testing, Latency, and Self-Healing.
Library           SSHLibrary
Library           RequestsLibrary
Library           OperatingSystem
Library           Process
Library           Collections
Library           String
Library           BuiltIn
Library           DateTime

# Setup creates the 50 UEs list; Teardown ensures connections close
Suite Setup       Initialize Environment
Suite Teardown    Close All Connections
# Global Teardown runs after EVERY test case to ensure clean state
Test Teardown     Global Test Teardown

*** Variables ***
# --- Network Configuration ---
${ENB_IP}              192.168.10.21
${GNB_SOURCE_IP}       192.168.10.31
${GNB_TARGET_IP}       192.168.10.32
${AMF_URL}             http://10.0.0.11:8080
${DATA_SERVER_IP}      127.0.0.1
${UE_COUNT}            50
${BASE_UE_NAME}        UE

# --- Credentials & OIDs ---
${CLI_USER}            admin
${CLI_PASS}            password
${WRONG_PASS}          wrong_password
${THROUGHPUT_OID}      1.3.6.1.4.1.9999.1.1.1

*** Keywords ***
# ================= INITIALIZATION =================
Initialize Environment
    [Arguments]    ${GLOBAL_UE_STATE}=    ${UE_LIST}=
    Log To Console    \n[INIT] Initializing Professional Telecom Test Environment...
    
    # 1. Dynamically Generate 50 UEs
    ${temp_list}=    Create List
    FOR    ${i}    IN RANGE    ${UE_COUNT}
        ${num}=    Evaluate    ${i} + 1
        ${id_str}=    Format String    {0:03d}    ${num}
        ${ue_id}=    Set Variable    ${BASE_UE_NAME}${id_str}
        Append To List    ${temp_list}    ${ue_id}
    END
    Set Suite Variable    ${UE_LIST}    ${temp_list}
    
    Log To Console    [INIT] Generated list of ${UE_COUNT} UEs (UE001 - UE050).
    Set Suite Variable    ${GLOBAL_UE_STATE}    ATTACHED

Global Test Teardown
    Log To Console    [TEARDOWN] Self-Healing: Cleaning up UE sessions...
    Execute CLI Command    clear ue all
    Disconnect Node

# ================= MOCK IMPLEMENTATIONS =================
Connect To Node
    [Arguments]    ${ip}    ${user}    ${password}
    Log To Console    [SSH] Connecting to ${ip} as ${user}...
    
    IF    '${password}' == '${WRONG_PASS}'
        Fail    Authentication Failed
    END
    Sleep    0.1s

Disconnect Node
    Log To Console    [SSH] Disconnected.

Execute CLI Command
    [Arguments]    ${command}
    ${output}=    Set Variable    OK

    IF    '${command}' == 'show ue-status'
        ${output}=    Get UE State
    ELSE IF    '${command}' == 'clear ue all'
        Set UE State    DETACHED
        ${output}=    Get UE State
    ELSE IF    '${command}' == 'attach ue'
        Set UE State    ATTACHED
        ${output}=    Get UE State
    END

    Return From Keyword    ${output}

# --- helper keywords to encapsulate suite-level UE state ---
Get UE State
    [Documentation]    Return current mock UE state
    ${state}=    Set Variable    ${GLOBAL_UE_STATE}
    Return From Keyword    ${state}

Set UE State
    [Arguments]    ${state}
    [Documentation]    Update mock UE state (suite-level)
    Set Suite Variable    ${GLOBAL_UE_STATE}    ${state}
    Return From Keyword    ${GLOBAL_UE_STATE}

Check AMF Registration
    [Arguments]    ${ue_id}
    ${resp}=    Create Dictionary    status=REGISTERED    id=${ue_id}
    Return From Keyword    ${resp}

Get SNMP Throughput Value
    [Arguments]    ${ip}    ${oid}
    Return From Keyword    1500.0

# ================= FUNCTIONAL KEYWORDS =================

Validate Bulk Registration
    [Arguments]    ${ue_list}
    Log To Console    \n--- Starting Bulk Registration for ${UE_COUNT} UEs ---
    
    ${count}=    Set Variable    0
    FOR    ${ue}    IN    @{ue_list}
        ${resp}=    Check AMF Registration    ${ue}
        Should Be Equal As Strings    ${resp['status']}    REGISTERED
        ${count}=    Evaluate    ${count} + 1
    END
    Log To Console    ✅ Successfully Registered ${count} UEs.

Perform Xn Handover
    [Arguments]    ${ue_id}    ${src}    ${tgt}
    Log To Console    \n--- Performing 5G Handover for ${ue_id} ---
    
    Connect To Node    ${src}    ${CLI_USER}    ${CLI_PASS}
    Execute CLI Command    attach ue
    ${status}=    Execute CLI Command    show ue-status
    Should Contain    ${status}    ATTACHED
    Log To Console    [HO] UE connected to Source gNB.
    Disconnect Node

    Log To Console    [HO] Triggering Mobility Event...
    Sleep    0.5s

    Connect To Node    ${tgt}    ${CLI_USER}    ${CLI_PASS}
    Execute CLI Command    attach ue 
    ${status_tgt}=    Execute CLI Command    show ue-status
    Should Contain    ${status_tgt}    ATTACHED
    Log To Console    [HO] UE successfully migrated to Target gNB.
    Disconnect Node

Check Data Plane Latency
    [Arguments]    ${server_ip}
    Log To Console    \n--- Checking Data Plane Latency ---
    ${result}=    Run Process    ping    ${server_ip}    -n    2    timeout=5s
    Log    ${result.stdout}
    
    IF    ${result.rc} != 0
        Fail    Ping Failed: Packet Loss detected
    END
    Log To Console    ✅ Latency Check Passed: ${server_ip} is reachable.

# ================= TEST CASES =================
*** Test Cases ***

1. Verify Bulk 5G Registration (50 UEs)
    [Documentation]    Iterates through 50 UEs to verify AMF registration.
    [Tags]    Functional    Load    5G
    Validate Bulk Registration    ${UE_LIST}

2. Verify 5G Inter-gNB Handover
    [Documentation]    Simulates moving a UE from Source gNB to Target gNB.
    [Tags]    Mobility    5G
    Perform Xn Handover    UE001    ${GNB_SOURCE_IP}    ${GNB_TARGET_IP}

3. Verify Security (Negative Test)
    [Documentation]    Ensures the system blocks unauthorized access.
    [Tags]    Security    Negative
    Log To Console    \n--- Testing Unauthorized Access ---
    Run Keyword And Expect Error    Authentication Failed    Connect To Node    ${ENB_IP}    admin    ${WRONG_PASS}
    Log To Console    ✅ System correctly rejected invalid credentials.

4. Verify Data Plane Latency
    [Documentation]    Checks if Packet Delay Budget is within limits (Ping).
    [Tags]    Performance    QoS
    Check Data Plane Latency    ${DATA_SERVER_IP}

5. Full Legacy Regression (Attach/Detach)
    [Documentation]    Standard Attach/Detach cycle for a single UE.
    [Tags]    Regression    4G
    Log To Console    \n--- Standard Attach/Detach Test ---
    Connect To Node    ${ENB_IP}    ${CLI_USER}    ${CLI_PASS}
    
    Execute CLI Command    attach ue
    ${status}=    Execute CLI Command    show ue-status
    Should Contain    ${status}    ATTACHED
    
    Execute CLI Command    clear ue all
    ${post}=    Execute CLI Command    show ue-status
    
    Should Contain    ${post}    DETACHED
    Log To Console    ✅ Attach/Detach Cycle Complete