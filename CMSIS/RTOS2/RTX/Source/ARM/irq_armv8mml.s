;/*
; * Copyright (c) 2016 ARM Limited. All rights reserved.
; *
; * SPDX-License-Identifier: Apache-2.0
; *
; * Licensed under the Apache License, Version 2.0 (the License); you may
; * not use this file except in compliance with the License.
; * You may obtain a copy of the License at
; *
; * http://www.apache.org/licenses/LICENSE-2.0
; *
; * Unless required by applicable law or agreed to in writing, software
; * distributed under the License is distributed on an AS IS BASIS, WITHOUT
; * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; * See the License for the specific language governing permissions and
; * limitations under the License.
; *
; * -----------------------------------------------------------------------------
; *
; * Project:     CMSIS-RTOS RTX
; * Title:       ARMv8M Mainline Exception handlers
; *
; * -----------------------------------------------------------------------------
; */


                IF       :LNOT::DEF:__FPU_USED
__FPU_USED      EQU      0
                ENDIF

                IF       :LNOT::DEF:__DOMAIN_NS
__DOMAIN_NS     EQU      0
                ENDIF

I_T_RUN_OFS     EQU      28                     ; osInfo.thread.run offset
TCB_SM_OFS      EQU      48                     ; TCB.stack_mem offset
TCB_SP_OFS      EQU      56                     ; TCB.SP offset
TCB_SF_OFS      EQU      34                     ; TCB.stack_frame offset
TCB_TZM_OFS     EQU      60                     ; TCB.tz_memory offset


                PRESERVE8
                THUMB


                AREA     |.constdata|, DATA, READONLY
                EXPORT   os_irq_cm
os_irq_cm       DCB      0                      ; Non weak library reference


                AREA     |.text|, CODE, READONLY


SVC_Handler     PROC
                EXPORT   SVC_Handler
                IMPORT   os_UserSVC_Table
                IMPORT   os_Info
                IF       __DOMAIN_NS = 1
                IMPORT   TZ_LoadContext_S
                ENDIF

                MRS      R0,PSP                 ; Get PSP
                LDR      R1,[R0,#24]            ; Load saved PC from stack
                LDRB     R1,[R1,#-2]            ; Load SVC number
                CBNZ     R1,SVC_User            ; Branch if not SVC 0

                PUSH     {R0,LR}                ; Save PSP and EXC_RETURN
                LDM      R0,{R0-R3,R12}         ; Load function parameters and address from stack
                BLX      R12                    ; Call service function
                POP      {R12,LR}               ; Restore PSP and EXC_RETURN
                STR      R0,[R12]               ; Store function return value

SVC_Context
                LDR      R3,=os_Info+I_T_RUN_OFS; Load address of os_Info.run
                LDM      R3,{R1,R2}             ; Load os_Info.thread.run: curr & next
                CMP      R1,R2                  ; Check if thread switch is required
                BXEQ     LR                     ; Exit when threads are the same

                IF       __FPU_USED = 1
                CBNZ     R1,SVC_ContextSave     ; Branch if running thread is not deleted
                TST      LR,#0x10               ; Check if extended stack frame
                BNE      SVC_ContextSwitch
                LDR      R1,=0xE000EF34         ; FPCCR Address
                LDR      R0,[R1]                ; Load FPCCR
                BIC      R0,#1                  ; Clear LSPACT (Lazy state)
                STR      R0,[R1]                ; Store FPCCR
                B        SVC_ContextSwitch
                ELSE
                CBZ      R1,SVC_ContextSwitch   ; Branch if running thread is deleted
                ENDIF

SVC_ContextSave
                STMDB    R12!,{R4-R11}          ; Save R4..R11
                IF       __FPU_USED = 1
                TST      LR,#0x10               ; Check if extended stack frame
                VSTMDBEQ R12!,{S16-S31}         ;  Save VFP S16.S31
                ENDIF

                STR      R12,[R1,#TCB_SP_OFS]   ; Store SP
                STRB     LR, [R1,#TCB_SF_OFS]   ; Store stack frame information

SVC_ContextSwitch
                STR      R2,[R3]                ; os_Info.thread.run: curr = next

SVC_ContextRestore
                LDR      R0,[R2,#TCB_SM_OFS]    ; Load stack memory base
                LDRB     R1,[R2,#TCB_SF_OFS]    ; Load stack frame information
                MSR      PSPLIM,R0              ; Set PSPLIM
                LDR      R0,[R2,#TCB_SP_OFS]    ; Load SP
                ORR      LR,R1,#0xFFFFFF00      ; Set EXC_RETURN

                IF       __FPU_USED = 1
                TST      LR,#0x10               ; Check if extended stack frame
                VLDMIAEQ R0!,{S16-S31}          ;  Restore VFP S16..S31
                ENDIF
                LDMIA    R0!,{R4-R11}           ; Restore R4..R11
                MSR      PSP,R0                 ; Set PSP

                IF       __DOMAIN_NS = 1
                LDR      R0,[R2,#TCB_TZM_OFS]   ; Load TrustZone memory identifier
                CBZ      R0,SVC_Exit            ; Branch if there is no secure context
                PUSH     {R4,LR}                ; Save EXC_RETURN
                BL       TZ_LoadContext_S       ; Load secure context
                POP      {R4,PC}                ; Exit from handler
                ENDIF

SVC_Exit
                BX       LR                     ; Exit from handler

SVC_User
                PUSH     {R4,LR}                ; Save registers
                LDR      R2,=os_UserSVC_Table   ; Load address of SVC table
                LDR      R3,[R2]                ; Load SVC maximum number
                CMP      R1,R3                  ; Check SVC number range
                BHI      SVC_Done               ; Branch if out of range

                LDR      R4,[R2,R1,LSL #2]      ; Load address of SVC function

                LDM      R0,{R0-R3}             ; Load function parameters from stack
                BLX      R4                     ; Call service function
                MRS      R4,PSP                 ; Get PSP
                STR      R0,[R4]                ; Store function return value

SVC_Done
                POP      {R4,PC}                ; Return from handler

                ALIGN
                ENDP


PendSV_Handler  PROC
                EXPORT   PendSV_Handler
                IMPORT   os_PendSV_Handler

                PUSH     {R4,LR}                ; Save EXC_RETURN
                BL       os_PendSV_Handler
                POP      {R4,LR}                ; Restore EXC_RETURN
                B        Sys_Context

                ALIGN
                ENDP


SysTick_Handler PROC
                EXPORT   SysTick_Handler
                IMPORT   os_Tick_Handler

                PUSH     {R4,LR}                ; Save EXC_RETURN
                BL       os_Tick_Handler        ; Call os_Tick_Handler
                POP      {R4,LR}                ; Restore EXC_RETURN
                B        Sys_Context

                ALIGN
                ENDP


Sys_Context     PROC
                EXPORT   Sys_Context
                IMPORT   os_Info
                IF       __DOMAIN_NS = 1
                IMPORT   TZ_LoadContext_S
                IMPORT   TZ_StoreContext_S
                ENDIF

                LDR      R3,=os_Info+I_T_RUN_OFS; Load address of os_Info.run
                LDM      R3,{R1,R2}             ; Load os_Info.thread.run: curr & next
                CMP      R1,R2                  ; Check if thread switch is required
                BXEQ     LR                     ; Exit when threads are the same

Sys_ContextSave
                IF       __DOMAIN_NS = 1
                TST      LR,#0x40               ; Check domain of interrupted thread
                BEQ      Sys_ContextSave1       ; Branch if non-secure
                LDR      R0,[R1,#TCB_TZM_OFS]   ; Load TrustZone memory identifier
                PUSH     {R1,R2,R3,LR}          ; Save registers and EXC_RETURN
                BL       TZ_StoreContext_S      ; Store secure context
                POP      {R1,R2,R3,LR}          ; Restore registers and EXC_RETURN
                MRS      R0,PSP                 ; Get PSP
                B        Sys_ContextSave2
                ENDIF

Sys_ContextSave1
                MRS      R0,PSP                 ; Get PSP
                STMDB    R0!,{R4-R11}           ; Save R4..R11
                IF       __FPU_USED = 1
                TST      LR,#0x10               ; Check if extended stack frame
                VSTMDBEQ R0!,{S16-S31}          ;  Save VFP S16.S31
                ENDIF

Sys_ContextSave2
                STR      R0,[R1,#TCB_SP_OFS]    ; Store SP
                STRB     LR,[R1,#TCB_SF_OFS]    ; Store stack frame information

Sys_ContextSwitch
                STR      R2,[R3]                ; os_Info.run: curr = next

Sys_ContextRestore
                LDR      R0,[R2,#TCB_SM_OFS]    ; Load stack memory base
                LDRB     R1,[R2,#TCB_SF_OFS]    ; Load stack frame information
                MSR      PSPLIM,R0              ; Set PSPLIM
                LDR      R0,[R2,#TCB_SP_OFS]    ; Load SP
                ORR      LR,R1,#0xFFFFFF00      ; Set EXC_RETURN

                IF       __FPU_USED = 1
                TST      LR,#0x10               ; Check if extended stack frame
                VLDMIAEQ R0!,{S16-S31}          ;  Restore VFP S16..S31
                ENDIF
                LDMIA    R0!,{R4-R11}           ; Restore R4..R11
                MSR      PSP,R0                 ; Set PSP

                IF       __DOMAIN_NS = 1
                LDR      R0,[R2,#TCB_TZM_OFS]   ; Load TrustZone memory identifier
                CBZ      R0,Sys_ContextExit     ; Branch if there is no secure context
                PUSH     {R4,LR}                ; Save EXC_RETURN
                BL       TZ_LoadContext_S       ; Load secure context
                POP      {R4,PC}                ; Exit from handler
                ENDIF

Sys_ContextExit
                BX       LR                     ; Exit from handler

                ALIGN
                ENDP


                END
