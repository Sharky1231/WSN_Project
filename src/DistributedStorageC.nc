#include <Timer.h>
#include "printf.h"
#include "DistributedStorage.h"
#include <UserButton.h>
module DistributedStorageC {
	uses interface Boot;
	uses interface Leds;
	uses interface Timer<TMilli> as SyncTimer;
	uses interface Timer<TMilli> as AckTimer;
	uses interface Timer<TMilli> as SendTimer;
	uses interface Timer<TMilli> as DieTimer;


	uses interface Packet;
	uses interface AMPacket;
	uses interface AMSend;
	uses interface SplitControl as AMControl;

	// Receive interface
	uses interface Receive;
	
	// Logger interface
	uses interface BlockRead;
	uses interface BlockWrite;
	
	uses interface Get<button_state_t>;
	uses interface Notify<button_state_t>;
	
}

implementation {
	// If struct which contains "message_t" variable is in different file then this one, 
	// it will throw "syntax error" for some reason
  
  	// Log data variable defined
  	LogDataMsg logData;
	
	bool current_broadcasting_node = FALSE;
	uint16_t number_of_ack_receiver_nodes = 0;
	
	bool synchronized = FALSE;
	
	uint16_t number_of_synchronized_nodes = 0; 
	uint16_t node_data;
		
	LogDataMsg node_data_array[N_NODES];
	
	// Variables for saving data -------------
	uint32_t address = 0;
	uint16_t offset[3] = {0};
	uint16_t readToAddr = 0;
	uint16_t addrCnt = 1;
	bool activeNode = FALSE;
	bool canIWrite = FALSE;
	bool firstRun = TRUE;
	bool readDoneFlag = FALSE;
	uint16_t i = 0;
	uint16_t receivedDataOffset = 0;
	bool isDead = FALSE;
	//-------------------------
	
	int readMoteID = 0;
	uint16_t readCnt = 0;
	bool allDataWasShared = FALSE;
	
	// Holds data for transmission
	message_t pkt;
	
	//Declaration of functions
	void sync_node();
	void send(uint16_t data, uint16_t dataMsgType);
	void send_received_data(uint16_t sender_node_id);
	void sync_msg_received(LogDataMsg log_data_msg);
	void data_msg_received(LogDataMsg data_msg);
	void done_msg_received(LogDataMsg log_data_msg);
	void ack_msg_received(LogDataMsg ack_msg);
	void save_requested_data(LogDataMsg save_msg);
	void simulateDeath();
	void resetVariables();
	void startProgram();
	void requestData();
	
	void resetVariables(){
		address = 0;
		offset[0] = 0;
		offset[1] = 0;
		offset[2] = 0;
		offset[3] = 0;
		readToAddr = 0;
		addrCnt = 1;
		activeNode = FALSE;
		canIWrite = FALSE;
		firstRun = TRUE;
		readDoneFlag = FALSE;
		i = 0;
		receivedDataOffset = 0;
		isDead = FALSE;
	}
	
	void startProgram(){
				//call AMControl.start();
		//call PrintTimer.startPeriodic(10000);
		call Notify.enable();
		printf("Erasing Flash\n");
		call BlockWrite.erase();	//We erase because if we want to store data in already written to parts of flash, we need to erase.
		
		node_data = TOS_NODE_ID;
		
		printf("\n\n\n\n---------------------- Distributed Storage Network ----------------------\n\n\n\n");
		
		printf("Note ID: %u. Total notes: %u\n", TOS_NODE_ID, N_NODES);
		
		//Broadcasting sync message if node has ID 1
		if(TOS_NODE_ID == 0) {
			current_broadcasting_node = TRUE;
			sync_node();
		}
	}
	
	void requestData(){
		send(0, NODE_REQUEST_DATA_MSG);
	}
	
	event void Boot.booted() {
		startProgram();
	}
	
	/* 
	 * Synchronizes with other node.
	 * Sends out a sync message as a periodic function, until all notes are synchronized
	 * Should only be used by node 0
	 * @param LogDataMsg received package
	 */
	void sync_node() {
		call SyncTimer.startPeriodic(NODE_PERIOD_MILLI);
	}
	
	//Synchronization timer is fired, sending NODE_SYNC_MSG if the desired number of synchronized nodes is not met
	//Stop the timer when the desired synchronized notes is met and starts broadcasting own data on the network
	//Should only be used by node 0
	//TODO Split into two SyncTimers, one for note 0 and one for other notes
	event void SyncTimer.fired() {
		printf("Broadcasting synchronization signal \n");
		if(TOS_NODE_ID == 0) {	
			//If not all other notes are synchronized
			if(number_of_synchronized_nodes < N_NODES - 1) {
				//call Leds.led0Toggle();
				number_of_synchronized_nodes = 0;
				if(allDataWasShared == FALSE){
					send(TOS_NODE_ID, NODE_SYNC_MSG);
				}
				else{
					
				}
			}
			else {
				printf("All %u nodes are now synchronized \n", N_NODES);
				//call Leds.led0Off();
				call SyncTimer.stop();
				//Starts the SendTimer, with a period of NODE_DATA_MSG_PERIOD_MILLI
				printf("Starting to send node data \n");
				call SendTimer.startPeriodic(NODE_PERIOD_MILLI);
			}
		}
		else {
			send(TOS_NODE_ID, NODE_SYNC_MSG);
		}	
	}
	
	event void AckTimer.fired()  {
		send(TOS_NODE_ID, NODE_ACK_MSG);
	}
	
	//TODO Be aware that all events are called first time after one period, so every event is delayed with one period as of now
	event void SendTimer.fired(){
		printf("Broadcasting own data on the network\n");
		number_of_ack_receiver_nodes = 0;
		send(node_data, NODE_DATA_MSG);
	}
	
	
	event void DieTimer.fired(){
		isDead = FALSE;
		call Leds.led2Toggle();
	}
	
	/* 
	 * Increments number_of_synchronized_nodes.
	 * Turns on a led corresponding to node id on sender of sync_msg.
	 * If the sync message was received from node 1, it sends out a sync_msg with timing relative to own node id 
	 * @param LogDataMsg received package
	 */
	void sync_msg_received(LogDataMsg sync_msg) {
		number_of_synchronized_nodes++;
		printf("Synchronization message received from node %u\n", sync_msg.nodeId);
		
		if(sync_msg.nodeId == 0) {
			printf("Broadcasting synchronization message in %u ms\n", (NODE_RESPONE_PERIOD_MILLI * TOS_NODE_ID));
    		synchronized = TRUE;
    		call SyncTimer.startOneShot(NODE_RESPONE_PERIOD_MILLI * TOS_NODE_ID);
		}
	}
	
	/* 
	 * Saves the received data_msg into node_data_array, if the data_msg is not from the node itself
	 * Sends acknowledge out on network, with timing relative to own node id 
	 * @param LogDataMsg received package
	 */
	void data_msg_received(LogDataMsg data_msg) {
		printf("Received data message from node %u, number received: ", data_msg.nodeId);
		printf("%u. Acknowledge fired \n", data_msg.data);
		node_data_array[data_msg.nodeId] = data_msg;
		
		switch (data_msg.nodeId) {				// Set the current address corresponding to the current mote.
			case 0:
			address = NODE_1_BASE_ADDR+offset[0];
			break;
			
			case 1:
			address = NODE_2_BASE_ADDR+offset[1];
			break;
			
			case 2:
			address = NODE_3_BASE_ADDR+offset[2];
			break;
			
			case 3:
			address = NODE_4_BASE_ADDR+offset[3];
			break;
			
			default:
			break;		
		}
		if(call BlockWrite.write(address, &node_data_array[data_msg.nodeId], sizeof(LogDataMsg)) == SUCCESS){	// Write to flash
		    	printf("Write SUCCESS\n");
		    }
		else{
			printf("Write FAIL\n");
		}
		offset[data_msg.nodeId] = offset[data_msg.nodeId]+6;	// Increment offset counter
					    
	   	call AckTimer.startOneShot(NODE_RESPONE_PERIOD_MILLI * TOS_NODE_ID);
	}
	
	/* 
	 * Increments number_of_ack_receiver_nodes, if all other nodes on the network has send a ack 
	 * a NODE_DONE_MSG is send and the SendTimer is canceled
	 * @param LogDataMsg received package
	 */
	//TODO Differentiate between which nodes ack, and only expect ack from missing notes
	//TODO Implement scheduling of NODE_DONE_MSG broadcast, if next node does not take over, eventually asking a new node to take over if nothing happens after some amount of retries
	void ack_msg_received(LogDataMsg ack_msg) {
		if(current_broadcasting_node) {
			printf("Acknowledge message received from node %u\n", ack_msg.nodeId);
		    number_of_ack_receiver_nodes++;
		    printf("%u Nodes ", number_of_ack_receiver_nodes);
		    printf("out of %u other nodes on the network has acknowledge the data message\n", N_NODES - 1);
		    
		    if(number_of_ack_receiver_nodes == N_NODES - 1) {
		    	printf("Sending done message\n");
		    	send(0, NODE_DONE_MSG);
		    	call SendTimer.stop();
		    	current_broadcasting_node = FALSE;
		    }
		}
	}
	
	/* 
	 * If the done_msg is received from a node with an id one less than the current node the node starts broadcasting its data
	 * @param LogDataMsg received package
	 */
	 //TODO Repeat node_data after some time 
	void done_msg_received(LogDataMsg done_msg) {
		if(done_msg.nodeId == TOS_NODE_ID - 1) {
			printf("Received done message from node %u, starting SendTimer\n", done_msg.nodeId);
			current_broadcasting_node = TRUE;
			call SendTimer.startPeriodic(NODE_PERIOD_MILLI);
		}
	}

	void send(uint16_t data, uint16_t dataMsgType) {
		LogDataMsg* packetToSend = (LogDataMsg*)(call Packet.getPayload(&pkt, sizeof (LogDataMsg)));
    	packetToSend->nodeId = TOS_NODE_ID;
    	packetToSend->dataMsgType = dataMsgType;
    	packetToSend->data = data;
    		    		
    	// Broadcast them,
    	if (call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(LogDataMsg)) == SUCCESS) {
    		//TODO Do confirmation of AMSend.send
    	}
	}
	
	//TODO implement send_received_data (broadcasting earlier received and stored data from another node on the network)
	void send_received_data(uint16_t sender_node_id) {
		//call Leds.led2Toggle();
		readMoteID = sender_node_id;
		printf("send_received_data Called with id %u\n", sender_node_id);
		switch(sender_node_id){
			case 0:
			address = NODE_1_BASE_ADDR;
			readToAddr = offset[0];
			break;
			
			case 1:
			address = NODE_2_BASE_ADDR;
			readToAddr = offset[1];
			break;
			
			case 2:
			address = NODE_3_BASE_ADDR;
			readToAddr = offset[2];
			break;
			
			case 3:
			address = NODE_4_BASE_ADDR;
			readToAddr = offset[3];
			break;
			
			default:
			break;			
		}
		
		//for(i = 0; i<readToAddr;i+6){
			//readDoneFlag = FALSE;
			if(call BlockRead.read(address, &node_data_array[sender_node_id], sizeof(LogDataMsg)) == SUCCESS){	//Read all the currently written data from a single partition
		    		printf("Read SUCCESS\n");
		    		

	    	}
	    	else{
	    		printf("Read FAIL\n");
	    		call Leds.led0On();
	    	}
	}
	// TODO Save the requested data
	void save_requested_data(LogDataMsg save_msg){
		printf("Received requested data message from node %u, number received: ", save_msg.nodeId);
		node_data_array[TOS_NODE_ID] = save_msg;
		call Leds.led0On();
		if(save_msg.nodeId == TOS_NODE_ID){
			switch(TOS_NODE_ID){
				case 0:
				address = NODE_1_BASE_ADDR;
				break;
				
				case 1:
				address = NODE_2_BASE_ADDR;
				break;
				
				case 2:
				address = NODE_3_BASE_ADDR;
				break;
				
				case 3:
				address = NODE_4_BASE_ADDR;
				break;
				
				default:
				break;
			}
			
			if(call BlockWrite.write(address+receivedDataOffset, &node_data_array[TOS_NODE_ID], sizeof(LogDataMsg)) == SUCCESS){	// Write to flash
			    	printf("Write SUCCESS\n");
			    }
			else{
				printf("Write FAIL\n");
			}
			receivedDataOffset = receivedDataOffset+6;	// Its never reset, but it is only used when the mote dies, then the counter resets because its stored in volatile
			//offset[TOS_NODE_ID] = receivedDataOffset;	// Update the motes own offset, as we dont sample data on the motes, no need
		}
	}
		
	event void AMControl.startDone(error_t err) {
		// Make sure AM started successfully
		if(err == SUCCESS) {
		}
		// If AM did not start or Log storage read was not successful
		else {
			call AMControl.start();
		}
	}
	
	event void AMControl.stopDone(error_t err) {
		
	}

	//TODO Do confirmation of AMSend.SendDone
	event void AMSend.sendDone(message_t * msg, error_t error) {
		
	}
		
	event message_t* Receive.receive(message_t * msg, void * payload, uint8_t len) {
		if(len == sizeof(LogDataMsg)) {
			//Get data from received packet
			LogDataMsg * recievedPacket = (LogDataMsg * ) payload;
			logData.nodeId = recievedPacket->nodeId;
			logData.dataMsgType = recievedPacket->dataMsgType;
			logData.data = recievedPacket->data;
		    
		    //If the message is not from the node itself
		    if(logData.nodeId != TOS_NODE_ID) {
		 	   //TODO Implement remaining MSG types
		    	switch (logData.dataMsgType) {
		    		case NODE_SYNC_MSG:
		    			sync_msg_received(logData);
		    		break;
		    	
		    		case NODE_ACK_MSG:
		    			ack_msg_received(logData);
		  		  	break;
		    	
		    		case NODE_DATA_MSG:
		    			data_msg_received(logData);
		    		break;
		    	
		    		case NODE_DONE_MSG:
		    			done_msg_received(logData);
		    		break;
		    	
		    		case NODE_REQUEST_DATA_MSG:
		    			
		    			send_received_data(logData.nodeId); // This function is failing
		    		break;
		  	  	
		    		case NODE_REQUESTED_DATA_MSG:
						save_requested_data(logData);
		    		break;
		    	
		    		default:
		    		break;
		    	}
		    	
		    }
		}
		
		return msg;
	}
	
	//Block interface methods
	event void BlockWrite.writeDone(storage_addr_t addr, void* buf, storage_len_t len, error_t error){
		call Leds.led1Toggle();
		//printf("Write DONE\n");

	    if(offset[0] == NODE_2_BASE_ADDR || offset[1] == NODE_3_BASE_ADDR || offset[2] == NODE_4_BASE_ADDR || offset[3] == MAX_NODE_ADDR){		// If partition is full
	    	offset[0] = 0;
	    	offset[1] = 0;
	    	offset[2] = 0;
	    	offset[3] = 0;
	    	printf("One of the partitions is full, ERASING Flash\n");	// How to save old data? We cannot loop without erasing the whole thing
	    	canIWrite = FALSE;	//Cannot write while erasing
	    	if(call BlockWrite.erase() == SUCCESS){
	    		printf("Erase Call SUCCESS\n");
	    	}
	    	else{
	    		printf("Erase Call FAIL\n");
	    	}
	    }
	    
	}
	
	event void BlockWrite.syncDone(error_t error){
	
	}
	
	event void BlockWrite.eraseDone(error_t error){
		printf("Flash Erased\n");
		canIWrite = TRUE;
		if(firstRun == TRUE){		// We dont want to call AMControl.start every time we erase flash, just on startup
			call AMControl.start();
			firstRun = FALSE;
		}
	}
	
	event void BlockRead.computeCrcDone(storage_addr_t addr, storage_len_t len, uint16_t crc, error_t error){
	}
	

	
	void simulateDeath(){
		call Leds.led1Toggle();
		printf("Going to turn off AM");
		isDead = TRUE;
		
		printf("Is dead");
		//call Leds.led1Toggle();
		
		//call DieTimer.startOneShot(2000); //Node will die in two seconds
		/*while(isDead == TRUE)
		{
			
		}*/
		
		//call Leds.led2Toggle();
		printf("Is alive.");
		resetVariables();		
		startProgram();
		requestData();
		printf("Data retrieved.");
		call Leds.led2Toggle();
	}
	
	event void Notify.notify(button_state_t val){
		if(val == BUTTON_PRESSED){
			simulateDeath();
			// IM DEAD		
		}
	}

	event void BlockRead.readDone(storage_addr_t addr, void *buf, storage_len_t len, error_t error){
		call Leds.led2On();
		printf("Sending out Requested data to node %u\n", readMoteID);
	    send(node_data_array[readMoteID].data, NODE_REQUESTED_DATA_MSG);
	    readCnt = readCnt + 6;
	    if(readCnt < offset[readMoteID]){
			if(call BlockRead.read(address+readCnt, &node_data_array[readMoteID], sizeof(LogDataMsg)) == SUCCESS){	//Read all the currently written data from a single partition
			    printf("Read SUCCESS\n");
	    	}
	    	else{
	    		printf("Read FAIL\n");
	    		call Leds.led0On();
	    	}
	    }	
	}
}
