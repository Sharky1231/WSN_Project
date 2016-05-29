#include <Timer.h>
#include "printf.h"
#include "DistributedStorage.h"
#include "TestSerial.h"
#include <UserButton.h>

module DistributedStorageC {
	uses interface Boot;
	uses interface Leds;
	uses interface Timer<TMilli> as SyncTimer;
	uses interface Timer<TMilli> as AckTimer;
	uses interface Timer<TMilli> as SendTimer;

	uses interface Packet;
	uses interface AMSend;
	uses interface SplitControl as AMControl;

	// Serial Com interface
	uses interface AMSend as SerialSend;
	uses interface Receive as SerialReceive;
	uses interface Packet as SerialPacket;
	uses interface BlockRead as SerialBlockRead;

	// Receive interface
	uses interface Receive;

	// Block interface
	uses interface BlockRead;
	uses interface BlockWrite;

	// Interfaces for button
	uses interface Get<button_state_t>;
	uses interface Notify<button_state_t>;

}

implementation {
	// If struct which contains "message_t" variable is in different file then this one,
	// it will throw "syntax error" for some reason

	// Struct for storing data
	LogDataMsg logData;
	LogDataMsg node_data_to_send;
	LogDataMsg node_data_array[N_NODES];

	// Holds data for transmission
	message_t pkt;

	bool current_broadcasting_node = FALSE;
	uint16_t number_of_ack_receiver_nodes = 0;

	bool synchronized = FALSE;
	uint16_t number_of_synchronized_nodes = 0;
	uint16_t node_data;

	test_serial_msg_t * serialComm;
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
	//-------------------------

	uint16_t baseAddress[3]={NODE_1_BASE_ADDR,NODE_2_BASE_ADDR,NODE_3_BASE_ADDR};
	uint8_t currentPartition;
	bool locked = FALSE;
	int readMoteID = 0;
	uint16_t readCnt = 0;
	bool allDataWasShared = FALSE;

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

	void resetVariables() {
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
	}

	void startProgram() {
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

	void requestData() {
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

	/* Synchronization timer is fired, send NODE_SYNC_MSG if the desired number of synchronized nodes is not met
	 * Stop the timer when the desired synchronized notes is met and starts broadcasting own data on the network
	 * Should only be used by node 0
	 */
	event void SyncTimer.fired() {
		printf("Broadcasting synchronization signal \n");
		if(TOS_NODE_ID == 0) {
			//If not all other notes are synchronized
			if(number_of_synchronized_nodes < N_NODES - 1) {
				number_of_synchronized_nodes = 0;
				if(allDataWasShared == FALSE) {
					send(TOS_NODE_ID, NODE_SYNC_MSG);
				}
				else {

				}
			}
			else {
				printf("All %u nodes are now synchronized \n", N_NODES);
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

	event void AckTimer.fired() {
		send(TOS_NODE_ID, NODE_ACK_MSG);
	}

	// Be aware that all events are called first time after one period, so every event is delayed with one period as of now
	event void SendTimer.fired() {
		printf("Broadcasting own data on the network\n");
		number_of_ack_receiver_nodes = 0;
		send(node_data, NODE_DATA_MSG);
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
			printf("Broadcasting synchronization message in %u ms\n",
					(NODE_RESPONE_PERIOD_MILLI * TOS_NODE_ID));
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

		switch(data_msg.nodeId){	// Set the current address corresponding to the current mote.
			case 0 : address = NODE_1_BASE_ADDR + offset[0];
			break;

			case 1 : address = NODE_2_BASE_ADDR + offset[1];
			break;

			case 2 : address = NODE_3_BASE_ADDR + offset[2];
			break;

			case 3 : address = NODE_4_BASE_ADDR + offset[3];
			break;

			default : break;
		}
		if(call BlockWrite.write(address, &node_data_array[data_msg.nodeId],
				sizeof(LogDataMsg)) == SUCCESS){	// Write to flash
			printf("Write SUCCESS\n");
		}
		else {
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
	void done_msg_received(LogDataMsg done_msg) {
		if(done_msg.nodeId == TOS_NODE_ID - 1) {
			printf("Received done message from node %u, starting SendTimer\n", done_msg.nodeId);
			current_broadcasting_node = TRUE;
			call SendTimer.startPeriodic(NODE_PERIOD_MILLI);
		}
	}

	void send(uint16_t data, uint16_t dataMsgType) {
		LogDataMsg * packetToSend = (LogDataMsg * )(call Packet.getPayload(&pkt,
				sizeof(LogDataMsg)));
		packetToSend->nodeId = TOS_NODE_ID;
		packetToSend->dataMsgType = dataMsgType;
		packetToSend->data = data;

		// Broadcast them
		if(call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(LogDataMsg)) == SUCCESS) {
		}
	}

	void send_received_data(uint16_t sender_node_id) {
		readMoteID = sender_node_id;
		printf("send_received_data Called with id %u\n", sender_node_id);
		switch(sender_node_id) {
			case 0 : address = NODE_1_BASE_ADDR;
			readToAddr = offset[0];
			break;

			case 1 : address = NODE_2_BASE_ADDR;
			readToAddr = offset[1];
			break;

			case 2 : address = NODE_3_BASE_ADDR;
			readToAddr = offset[2];
			break;

			case 3 : address = NODE_4_BASE_ADDR;
			readToAddr = offset[3];
			break;

			default : break;
		}

		if(call BlockRead.read(address, &node_data_array[sender_node_id],
				sizeof(LogDataMsg)) == SUCCESS){	//Read all the currently written data from a single partition
			printf("Read SUCCESS\n");
		}
		else {
			printf("Read FAIL\n");
			call Leds.led0On();
		}
	}

	void save_requested_data(LogDataMsg save_msg) {
		printf("Received requested data message from node %u, number received: ",
				save_msg.nodeId);
		node_data_array[TOS_NODE_ID] = save_msg;
		call Leds.led0On();
		if(save_msg.nodeId == TOS_NODE_ID) {
			switch(TOS_NODE_ID) {
				case 0 : address = NODE_1_BASE_ADDR;
				break;

				case 1 : address = NODE_2_BASE_ADDR;
				break;

				case 2 : address = NODE_3_BASE_ADDR;
				break;

				case 3 : address = NODE_4_BASE_ADDR;
				break;

				default : break;
			}

			if(call BlockWrite.write(address + receivedDataOffset,
					&node_data_array[TOS_NODE_ID], sizeof(LogDataMsg)) == SUCCESS){	// Write to flash
				printf("Write SUCCESS\n");
			}
			else {
				printf("Write FAIL\n");
			}
			receivedDataOffset = receivedDataOffset + 6;	// Its never reset, but it is only used when the mote dies, then the counter resets because its stored in volatile
		}
	}

	event void AMControl.startDone(error_t err) {
		if(err == SUCCESS) {
		}
		else {
			call AMControl.start();
		}
	}

	event void AMControl.stopDone(error_t err) {
	}

	event void AMSend.sendDone(message_t * msg, error_t error) {
	}

	event message_t * Receive.receive(message_t * msg, void * payload,
			uint8_t len) {
		if(len == sizeof(LogDataMsg)) {
			//Get data from received packet
			LogDataMsg * recievedPacket = (LogDataMsg * ) payload;
			logData.nodeId = recievedPacket->nodeId;
			logData.dataMsgType = recievedPacket->dataMsgType;
			logData.data = recievedPacket->data;

			//If the message is not from the node itself
			if(logData.nodeId != TOS_NODE_ID) {
				switch(logData.dataMsgType) {
					case NODE_SYNC_MSG : sync_msg_received(logData);
					break;
					case NODE_ACK_MSG : ack_msg_received(logData);
					break;

					case NODE_DATA_MSG : data_msg_received(logData);
					break;

					case NODE_DONE_MSG : done_msg_received(logData);
					break;

					case NODE_REQUEST_DATA_MSG : send_received_data(logData.nodeId);
					break;

					case NODE_REQUESTED_DATA_MSG : save_requested_data(logData);
					break;

					default : break;
				}

			}
		}

		return msg;
	}


	// this is for the serial message from PC
	event message_t* SerialReceive.receive(message_t * msg, void * payload, uint8_t len) {
		call Leds.led0On();
		printf("I received a serial request\n");
		if(len == sizeof(test_serial_msg_t)) {
			
			test_serial_msg_t * recievedPacket = (test_serial_msg_t * ) payload;	
			if (recievedPacket->comm == FLASH){
				printf("I'm reading my flash memory'\n");	
				call Leds.led1On();
				readMoteID=0;
				address=baseAddress[recievedPacket->data];
				readMoteID=recievedPacket->data;
				if(call SerialBlockRead.read(address+readCnt, &node_data_array[readMoteID], sizeof(LogDataMsg)) == SUCCESS){	//Read all the currently written data from a single partition
					printf("Read SUCCESS\n");	
				}	
			}	
		}
		return msg;
	}
	
	event void SerialBlockRead.readDone(storage_addr_t addr, void *buf, storage_len_t len, error_t error){
		test_serial_msg_t* packetToSend = (test_serial_msg_t*)(call SerialPacket.getPayload(&pkt, sizeof (test_serial_msg_t)));	
		call Leds.led2On();	
		packetToSend->comm = FLASHRESPONSE; //check that java knows this
		packetToSend->data = node_data_array[readMoteID].data;

		if (call SerialSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(test_serial_msg_t)) == SUCCESS) {
			locked = TRUE;
		}
	}
	
	event void SerialSend.sendDone(message_t* bufPtr, error_t error) {
		call Leds.led0Off();
		call Leds.led1Off();
 		call Leds.led2Off();
 		printf("Serial Send done\n");
		locked = FALSE;
		readCnt = readCnt + 6;
		if(readCnt < offset[readMoteID] && address<baseAddress[4]){
			if(call BlockRead.read(address+readCnt, &node_data_array[readMoteID], sizeof(LogDataMsg)) == SUCCESS){	//Read all the currently written data from a single partition
				call Leds.led2Toggle();				
			}else{
				printf("Read FAIL\n");
			}
		}else{
			printf("Error\n");
		}		
	}
	
	//Block interface methods
	event void BlockWrite.writeDone(storage_addr_t addr, void * buf, storage_len_t len, error_t error) {
		call Leds.led1Toggle();

		if(offset[0] == NODE_2_BASE_ADDR || offset[1] == NODE_3_BASE_ADDR || offset[2] == NODE_4_BASE_ADDR || offset[3] == MAX_NODE_ADDR){	// If partition is full
			offset[0] = 0;
			offset[1] = 0;
			offset[2] = 0;
			offset[3] = 0;
			printf("One of the partitions is full, ERASING Flash\n");
			canIWrite = FALSE;	//Cannot write while erasing
			if(call BlockWrite.erase() == SUCCESS) {
				printf("Erase Call SUCCESS\n");
			}
			else {
				printf("Erase Call FAIL\n");
			}
		}

	}

	event void BlockWrite.syncDone(error_t error) {
	}

	event void BlockWrite.eraseDone(error_t error) {
		printf("Flash Erased\n");
		canIWrite = TRUE;
		if(firstRun == TRUE){	// We dont want to call AMControl.start every time we erase flash, just on startup
			call AMControl.start();
			firstRun = FALSE;
		}
	}

	event void BlockRead.computeCrcDone(storage_addr_t addr, storage_len_t len,
			uint16_t crc, error_t error) {
	}

	void simulateDeath() {
		call Leds.led1Toggle();
		printf("Is dead");

		resetVariables();
		startProgram();
		requestData();

		printf("Data retrieved.");
		call Leds.led2Toggle();
	}

	event void Notify.notify(button_state_t val) {
		if(val == BUTTON_PRESSED) {
			simulateDeath();
		}
	}

	event void BlockRead.readDone(storage_addr_t addr, void * buf,
			storage_len_t len, error_t error) {
		call Leds.led2On();
		printf("Sending out Requested data to node %u\n", readMoteID);
		send(node_data_array[readMoteID].data, NODE_REQUESTED_DATA_MSG);
		readCnt = readCnt + 6;
		if(readCnt < offset[readMoteID]) {
			if(call BlockRead.read(address + readCnt, &node_data_array[readMoteID],
					sizeof(LogDataMsg)) == SUCCESS){	//Read all the currently written data from a single partition
				printf("Read SUCCESS\n");
			}
			else {
				printf("Read FAIL\n");
				call Leds.led0On();
			}
		}
	}
	
		event void SerialBlockRead.computeCrcDone(storage_addr_t addr, storage_len_t len, uint16_t crc, error_t error){
	}
	
	
}
