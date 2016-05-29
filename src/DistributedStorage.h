#ifndef DISTRIBUTEDSTORAGE_H
#define DISTRIBUTEDSTORAGE_H

enum {
	N_NODES = 2,
	NODE_RESPONE_PERIOD_MILLI = 1000,
	NODE_PERIOD_MILLI = 5000,
	//AM_LOGDATAMSG = 16,
	AM_BLINKTORADIO = 6,
	NODE_SYNC_MSG = 0,
	NODE_ACK_MSG = 1,
	NODE_DONE_MSG = 2,
	NODE_DATA_MSG = 3,
	NODE_REQUEST_DATA_MSG = 4,
	NODE_REQUESTED_DATA_MSG = 5,
	NODE_1_BASE_ADDR = 0,			//256kB devided by 4 = 65536 bit = 8192 byte, total 32.768
	NODE_2_BASE_ADDR = 8192,
	NODE_3_BASE_ADDR = 16384,	
	NODE_4_BASE_ADDR = 24576,
	MAX_NODE_ADDR = 32768
};

// If "message_T" is part of the struct, then for some reason it can't send the packet
typedef nx_struct LogDataMsg {
	//message_t msg;
	nx_uint16_t nodeId;
	nx_uint16_t dataMsgType;
	nx_uint16_t data;
} LogDataMsg;

typedef nx_struct NodeData {
	nx_uint16_t nodeId;
	nx_uint16_t data;
} NodeData;

//  typedef nx_struct RadioMessageStruct {
//    nx_uint16_t nodeId;
//    nx_uint16_t counter;
//    nx_uint32_t relativeTime;
//    nx_uint8_t batteryLVL;
//    nx_uint8_t powerLVL;
//    nx_uint16_t seqNum;
//    message_t type;
//    nx_uint8_t value;
//  } RadioMessageStruct;   

#endif
