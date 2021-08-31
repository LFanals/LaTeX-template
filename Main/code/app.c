/*
*********************************************************************************************************
*                                            EXAMPLE CODE
*
*                          (c) Copyright 2009-2015; Micrium, Inc.; Weston, FL
*
*               All rights reserved.  Protected by international copyright laws.
*
*               Please feel free to use any application code labeled as 'EXAMPLE CODE' in
*               your application products.  Example code may be used as is, in whole or in
*               part, or may be used as a reference only.
*
*               Please help us continue to provide the Embedded community with the finest
*               software available.  Your honesty is greatly appreciated.
*
*               You can contact us at www.micrium.com.
*********************************************************************************************************
*/

/*
*********************************************************************************************************
*                                          SETUP INSTRUCTIONS
*
*   This demonstration project illustrate a basic uC/OS-III project with simple "hello world" output.
*
*   By default some configuration steps are required to compile this example :
*
*   1. Include the require Micrium software components
*       In the BSP setting dialog in the "overview" section of the left pane the following libraries
*       should be added to the BSP :
*
*           ucos_common
*           ucos_osiii
*           ucos_standalone
*
*   2. Kernel tick source - (Not required on the Zynq-7000 PS)
*       If a suitable timer is available in your FPGA design it can be used as the kernel tick source.
*       To do so, in the "ucos" section select a timer for the "kernel_tick_src" configuration option.
*
*   3. STDOUT configuration
*       Output from the print() and UCOS_Print() functions can be redirected to a supported UART. In
*       the "ucos" section the stdout configuration will list the available UARTs.
*
*   Troubleshooting :
*       By default the Xilinx SDK may not have selected the Micrium drivers for the timer and UART.
*       If that is the case they must be manually selected in the drivers configuration section.
*
*       Finally make sure the FPGA is programmed before debugging.
*
*
*   Remember that this example is provided for evaluation purposes only. Commercial development requires
*   a valid license from Micrium.
*********************************************************************************************************
*/


/*
*********************************************************************************************************
*                                            INCLUDE FILES
*********************************************************************************************************
*/

#include  <stdio.h>
#include  <Source/os.h>
#include  <ucos_bsp.h>

#include "xadcps.h"
#include <xgpio.h>


/*
*********************************************************************************************************
*                                            DEFINES
*********************************************************************************************************
*/

#define XADC_DEVICE_ID 		XPAR_XADCPS_0_DEVICE_ID
#define GPIO_DEVICE_ID		XPAR_AXI_GPIO_0_DEVICE_ID
#define BUTTON_CHANNEL		1 // Input channel of the GPIO (check this is consistent with the block diagram)
#define TEMPERATURE_CHANNEL		2 // Output channel of the GPIO (check this is consistent with the block diagram)
#define	APP_TASK_START_STK_SIZE	512u
#define	APP_TASK1_STK_SIZE		512u
#define APP_TASK2_STK_SIZE		512u
#define APP_TASK_START_PRIO		8u
#define APP_TASK1_PRIO			2u
#define APP_TASK2_PRIO			3u


/*
*********************************************************************************************************
*                                            LOCAL VARIABLES
*********************************************************************************************************
*/

static  OS_TCB       AppTaskStartTCB;							// Task Control Block (TCB).
static  OS_TCB       AppTask1TCB;
static  OS_TCB       AppTask2TCB;

static  CPU_STK      AppTaskStartStk[APP_TASK_START_STK_SIZE]; 	 // Startup Task Stack
static  CPU_STK      AppTask1Stk[APP_TASK1_STK_SIZE];			 // Task #1      Stack
static  CPU_STK      AppTask2Stk[APP_TASK2_STK_SIZE];			 // Task #2      Stack

static  OS_MUTEX     AppMutexPrint;							     // App Mutex

static XAdcPs XAdcInst;      								     // XADC Driver instance
XAdcPs *XAdcInstPtr = &XAdcInst;
static XGpio Gpio; 												// GPIO Driver instance

// Global variable that holds the output
int output = 0; // 32 bit variable, contains 23 useful bits. threshold(11b)|temperature(11b)|alarm(1b)
int threshold; // temperature threshold
int temperature; // last read temperature value
int alarm; // holds 1 if there's an alarm (temperature > threshold)


/*
*********************************************************************************************************
*                                      LOCAL FUNCTION PROTOTYPES
*********************************************************************************************************
*/

static  void  AppTaskCreate      (void);
static  void  AppTaskStart       (void *p_arg);
static  void  AppTask1           (void *p_arg);
static  void  AppTask2           (void *p_arg);
static  void  AppPrintWelcomeMsg (void);
static  void  AppPrint           (char *str);
static  void  AppPrintWelcomeMsg (void);
static void Peripheral_Init		(void); //initialization of the peripheral unit for the XadcPs
void  MainTask (void *p_arg);

/*
*********************************************************************************************************
*                                               main()
*
* Description : Entry point for C code.
*
*********************************************************************************************************
*/

int main()
{
	threshold = 50;				// Initialize threshold, for practicality purposes

	UCOSStartup(MainTask);

	return 0;
}

/*
*********************************************************************************************************
*                                          STARTUP TASK
*
* Description : This is an example of a startup task.
*
* Arguments   : p_arg   is the argument passed to 'AppTaskStart()' by 'OSTaskCreate()'.
*
* Returns     : none
*
* Notes       :
*********************************************************************************************************
*/
void  MainTask (void *p_arg)
{
    OS_ERR       err;

    AppPrintWelcomeMsg();

	OSInit(&err);		/* Initialize uC/OS-III.                                */

	OSTaskCreate	((OS_TCB	*)&AppTaskStartTCB,
					(CPU_CHAR	*)"App Task Start",
					(OS_TASK_PTR )AppTaskStart,
					(void		*)0,
					(OS_PRIO	 )APP_TASK_START_PRIO,
					(CPU_STK 	*)&AppTaskStartStk[0],
					(CPU_STK_SIZE)APP_TASK_START_STK_SIZE / 10,
					(CPU_STK_SIZE)APP_TASK_START_STK_SIZE,
					(OS_MSG_QTY	 )0,
					(OS_TICK	 )0,
					(void 		*)0,
					(OS_OPT )(OS_OPT_TASK_STK_CHK | OS_OPT_TASK_STK_CLR),
					(OS_ERR *)&err);

	OSStart(&err);			/* Start multitasking (i.e. give control to uC/OS-II).  */

	while (1) {
		AppPrint(".");
	        ;
	    }
}

/*
*********************************************************************************************************
*                                        PRINT WELCOME THROUGH UART
*
* Description : Prints a welcome message through the UART.
*
* Argument(s) : none
*
* Return(s)   : none
*
* Caller(s)   : application functions.
*
* Note(s)     : Because the welcome message gets displayed before
*               the multi-tasking has started, it is safe to access
*               the shared resource directly without any mutexes.
*********************************************************************************************************
*/

static  void  AppPrintWelcomeMsg (void)
{
    UCOS_Print("\f\f\r\n");
    UCOS_Print("Micrium\r\n");
    UCOS_Print("uCOS-III\r\n\r\n");
    UCOS_Print("This application runs three different tasks:\r\n\r\n");
    UCOS_Print("1. Task Start: Initializes the OS and creates tasks and\r\n");
    UCOS_Print("               other kernel objects such as the mutex.\r\n");
    UCOS_Print("               This task remains running and printing a\r\n");
    UCOS_Print("               dot '.' every 100 milliseconds.\r\n");
    UCOS_Print("2. Task #1   : Reads temperature every 200-milliseconds.\r\n");
    UCOS_Print("3. Task #2   : Reads input buttons every 500-milliseconds.\r\n\r\n");
}

/*
*********************************************************************************************************
*                                          STARTUP TASK
*
* Description : This is an example of a startup task.  As mentioned in the book's text, you MUST
*               initialize the ticker only once multitasking has started.
*
* Arguments   : p_arg   is the argument passed to 'AppTaskStart()' by 'OSTaskCreate()'.
*
* Returns     : none
*
* Notes       : 1) The first line of code is used to prevent a compiler warning because 'p_arg' is not
*                  used.  The compiler should not generate any code for this statement.
*********************************************************************************************************
*/

static  void  AppTaskStart (void *p_arg)
{
    OS_ERR    err;

	UCOS_Print("Task Start Created\r\n");

    AppTaskCreate();                                            /* Create Application tasks                             */
    OSMutexCreate((OS_MUTEX *)&AppMutexPrint, (CPU_CHAR *)"My App. Mutex", (OS_ERR *)&err);

    while (1) {                                            /* Task body, always written as an infinite loop.       */

        OSTimeDlyHMSM(0, 0, 0, 100,
                      OS_OPT_TIME_HMSM_STRICT,
                     &err);                                     /* Waits 100 milliseconds.                              */

    	AppPrint(".");                                          /* Prints a dot every 100 milliseconds.                 */
    }
}

/*
*********************************************************************************************************
*                                       CREATE APPLICATION TASKS
*
* Description : Creates the application tasks.
*
* Argument(s) : none
*
* Return(s)   : none
*
* Caller(s)   : AppTaskStart()
*
* Note(s)     : none.
*********************************************************************************************************
*/

static  void  AppTaskCreate (void)
{
	OS_ERR  err;


    OSTaskCreate((OS_TCB     *)&AppTask1TCB,                    /* Create the Task #1.                                  */
                 (CPU_CHAR   *)"Task 1",
                 (OS_TASK_PTR ) AppTask1,
                 (void       *) 0,
                 (OS_PRIO     ) APP_TASK1_PRIO,
                 (CPU_STK    *)&AppTask1Stk[0],
                 (CPU_STK_SIZE) APP_TASK1_STK_SIZE / 10u,
                 (CPU_STK_SIZE) APP_TASK1_STK_SIZE,
                 (OS_MSG_QTY  ) 0u,
                 (OS_TICK     ) 0u,
                 (void       *) 0,
                 (OS_OPT      )(OS_OPT_TASK_STK_CHK | OS_OPT_TASK_STK_CLR),
                 (OS_ERR     *)&err);

    OSTaskCreate((OS_TCB     *)&AppTask2TCB,                    /* Create the Task #2.                                  */
                 (CPU_CHAR   *)"Task 2",
                 (OS_TASK_PTR ) AppTask2,
                 (void       *) 0,
                 (OS_PRIO     ) APP_TASK2_PRIO,
                 (CPU_STK    *)&AppTask2Stk[0],
                 (CPU_STK_SIZE) APP_TASK2_STK_SIZE / 10u,
                 (CPU_STK_SIZE) APP_TASK2_STK_SIZE,
                 (OS_MSG_QTY  ) 0u,
                 (OS_TICK     ) 0u,
                 (void       *) 0,
                 (OS_OPT      )(OS_OPT_TASK_STK_CHK | OS_OPT_TASK_STK_CLR),
                 (OS_ERR     *)&err);
}

/*
*********************************************************************************************************
*                                              TASK #1
*
* Description : This is an example of an application task that prints "1" every second to the UART.
*
*
* Arguments   : p_arg   is the argument passed to 'AppTaskStart()' by 'OSTaskCreate()'.
*
* Returns     : none
*
* Notes       : 1) The first line of code is used to prevent a compiler warning because 'p_arg' is not
*                  used.  The compiler should not generate any code for this statement.
*********************************************************************************************************
*/

static  void  AppTask1 (void *p_arg) // Temperature task
{
	OS_ERR  err;

	unsigned int temperature_raw;
	(void)p_arg;
	char temp_string[20]; // Holds the temperature, it is later printed
	char temp_string_pixels[20]; // Holds the temperature, it is later printed
	char t_temp_string[20]; // Holds the temperature threshold, it is later printed
	char t_temp_string_pixels[20]; // Holds the temperature threshold, it is later printed
	char alarm_string[20];

    AppPrint("Temperature task has started\r\n");
    Peripheral_Init();
    while (1) {
                                           		/* Task body, always written as an infinite loop. */

    temperature_raw = XAdcPs_GetAdcData(XAdcInstPtr, XADCPS_CH_TEMP);
    temperature = (int) XAdcPs_RawToTemperature(temperature_raw);

    // Print read temperature
	sprintf(temp_string, "%d", temperature);
	AppPrint("\n Temperature: ");
	AppPrint(temp_string);

	sprintf(temp_string_pixels, "%u", temperature<<4);
	AppPrint("\n Temperature pixels: ");
	AppPrint(temp_string_pixels);

    // Print threshold
	sprintf(t_temp_string, "%d", threshold & 0x7F);
	AppPrint("\n Threshold: ");
	AppPrint(t_temp_string);

    // Print threshold
	sprintf(t_temp_string_pixels, "%u", (threshold & 0x7F)<<4);
	AppPrint("\n Threshold pixels: ");
	AppPrint(t_temp_string_pixels);

	// Compare temperature against threshold
	if (temperature > threshold){
		alarm = 1;
	}
	else {
		alarm = 0;
	}

    // Print alarm
	sprintf(alarm_string, "%d", alarm);
	AppPrint("\n alarm: ");
	AppPrint(alarm_string);


	output = (alarm & 0x1)<<22|(temperature & 0x7F)<<(4+11)|(threshold & 0x7F)<<(4); // Concatenate the variables to get 23 useful bits to output port


        OSTimeDlyHMSM(0, 0, 0, 200,
                      OS_OPT_TIME_HMSM_STRICT,
                     &err);
           // AppPrint("1");

     XGpio_DiscreteWrite(&Gpio,TEMPERATURE_CHANNEL,output);		// Write the output in the gpio output channel


    }
}



/*
*********************************************************************************************************
*                                               TASK #2
*
* Description : This is an example of an application task that prints "2" every 2 seconds to the UART.
*
* Arguments   : p_arg   is the argument passed to 'AppTaskStart()' by 'OSTaskCreate()'.
*
* Returns     : none
*
* Notes       : 1) The first line of code is used to prevent a compiler warning because 'p_arg' is not
*                  used.  The compiler should not generate any code for this statement.
*********************************************************************************************************
*/

static  void  AppTask2 (void *p_arg) // This is the responsible for the buttons
{
	OS_ERR  err;


	(void)p_arg;
	int button=0;


    AppPrint("Buttons task has started \r\n");
    Peripheral_Init();
	while (1) {

	button = XGpio_DiscreteRead(&Gpio, BUTTON_CHANNEL);	// Reads the input channel of the gpio to determine if a button has been pressed

	// // Display read button value (0 if any button is pressed)
	// char button_string[20];
	// AppPrint("\n BUT ");
	// sprintf(button_string, "%d", button);
	// AppPrint(button_string);

		if(button == 1) { // BTNL button pressed, decrease threshold by 1C
			threshold = threshold-1;
			AppPrint("Threshold - 1 \r\n");
			}
		else if (button == 2){ // BTNR button pressed, increase threshold by 1C
			threshold = threshold+1;
			AppPrint("Threshold + 1 \r\n");
		}


		output = (alarm & 0x1)<<22|(temperature & 0x7F)<<(4+11)|(threshold & 0x7F)<<(4); // Concatenate the variables to get 23 useful bits to output port


	XGpio_DiscreteWrite(&Gpio,TEMPERATURE_CHANNEL,output); // write in the gpio output channel


                                               		/* Task body, always written as an infinite loop.       */

        OSTimeDlyHMSM(0, 0, 0, 500,
                      OS_OPT_TIME_HMSM_STRICT,
                     &err);                                     /* Waits for 2 seconds.                                 */

    	// AppPrint("2");                                          /* Prints 2 to the UART.                                */

		}
	}



/*
*********************************************************************************************************
*                                            PRINT THROUGH UART
*
* Description : Prints a string through the UART. It makes use of a mutex to
*               access this shared resource.
*
* Argument(s) : none
*
* Return(s)   : none
*
* Caller(s)   : application functions.
*
* Note(s)     : none.
*********************************************************************************************************
*/

static  void  AppPrint (char *str)
{
	OS_ERR  err;
    CPU_TS  ts;


                                                                /* Wait for the shared resource to be released.         */
    OSMutexPend(	(OS_MUTEX *)&AppMutexPrint,
    				(OS_TICK )0u,                                            /* No timeout.                                          */
					(OS_OPT )OS_OPT_PEND_BLOCKING,                          /* Block if not available.                              */
					(CPU_TS *)&ts,                                            /* Timestamp.                                           */
					(OS_ERR *)&err);

    UCOS_Print(str);                                                 /* Access the shared resource.                          */

                                                                /* Releases the shared resource.                        */
    OSMutexPost( 	(OS_MUTEX *)&AppMutexPrint,
    				(OS_OPT )OS_OPT_POST_NONE,                              /* No options.                                          */
					(OS_ERR *)&err);
}

void Peripheral_Init()
{
	int Status;
	XAdcPs_Config *ConfigPtr;

    /* Initialize the GPIO driver. If an error occurs then exit */
    	Status = XGpio_Initialize(&Gpio, GPIO_DEVICE_ID);
    	if (Status != XST_SUCCESS) {
    		return XST_FAILURE;
    	}

    	/*
    	 * Perform a self-test on the GPIO.  This is a minimal test and only
    	 * verifies that there is not any bus error when reading the data
    	 * register
    	 */
    	XGpio_SelfTest(&Gpio);

    	/*
    	 * Setup direction register so the switch is an input and the LED is
    	 * an output of the GPIO
    	 */
    	XGpio_SetDataDirection(&Gpio, BUTTON_CHANNEL, 0xff); // Establish BUTTON_CHANNEL as an input

    	XGpio_SetDataDirection(&Gpio, TEMPERATURE_CHANNEL, 0x00); // Establish TEMPERATURE_CHANNEL as an output


    	/*
    	 * Initialize the XAdc driver.
    	 */
    	ConfigPtr = XAdcPs_LookupConfig(XADC_DEVICE_ID);


    	XAdcPs_CfgInitialize(XAdcInstPtr, ConfigPtr,
    				ConfigPtr->BaseAddress);

    	/*
    	 * Self Test the XADC/ADC device
    	 */
    	Status = XAdcPs_SelfTest(XAdcInstPtr);


    	/*
    	 * Disable the Channel Sequencer before configuring the Sequence
    	 * registers.
    	 */
    	XAdcPs_SetSequencerMode(XAdcInstPtr, XADCPS_SEQ_MODE_SAFE);

}

