/*
 * Copyright (c) 2010, CISTER/ISEP - Polytechnic Institute of Porto
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 * - Neither the name of the Technische Universitaet Berlin nor the names
 *   of its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
 * OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
 * USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * 
 * 
 * 
 * @author Ricardo Severino <rars@isep.ipp.pt>
 * @author Stefano Tennina <sota@isep.ipp.pt>
 * ========================================================================
 */

#include "TKN154.h"
#include "app_profile.h"
#include "printf.h"

module TestCoordC
{
  uses {
    interface Boot;
    interface MCPS_DATA;
    interface MLME_RESET;
    interface MLME_START;
    interface MLME_SET;
    interface MLME_ASSOCIATE;
    interface MLME_GET;
    interface IEEE154Frame as Frame;
    interface IEEE154TxBeaconPayload;
    interface Leds;
    interface MLME_GTS;
    interface Packet;
  }
}
implementation 
{
  bool m_ledCount;
  uint8_t m_payloadLen;

  uint8_t m_gotSlot;
  uint8_t m_messageCount;
  message_t m_frame;
  ieee154_address_t m_destAddr;
  message_t gts_frame;
  ieee154_address_t m_dstAddr;
  uint8_t *payloadRegion;
  uint16_t m_assignedShortAddress = 0;
	typedef struct {
		uint16_t node_id;
		unsigned char message_payload : 6;
	} gts_message_st;
  task void packetSendTask()
  {
    call Frame.setAddressingFields(
          &m_frame,                
          ADDR_MODE_SHORT_ADDRESS,        // SrcAddrMode,
          ADDR_MODE_SHORT_ADDRESS,        // DstAddrMode,
          call MLME_GET.macPANId(),     // DstPANId,
          &m_dstAddr,  // DstAddr,
          NULL                            // security
          );
    m_messageCount++; 
    if (m_messageCount <  10) {
      call MCPS_DATA.request  (
          &m_frame,                         // frame,
          m_payloadLen,                     // payloadLength,
          0,                                // msduHandle,
          TX_OPTIONS_ACK | TX_OPTIONS_GTS // TxOptions,
          );    
    }
  }
	void GtsGetCharacteristics(uint8_t gtsCharacteristics, uint8_t * gtsLength,
			bool * gtsDirection, bool * characteristicType) {
		*gtsLength = gtsCharacteristics & 0b00001111;
		*gtsDirection = (gtsCharacteristics & 0b00010000) >> 4;
		*characteristicType = (gtsCharacteristics & 0b00100000) >> 5;
	}
  void askNodeToRequestGTS(uint8_t gtsCharacteristics, ieee154_address_t destAddr) {
   uint8_t header;
   gts_message_st* gts_message = (gts_message_st*)malloc(sizeof(gts_message_st));
   uint16_t fullPayload;
   void* payloadPointer;
   		uint8_t gtsLength = 0;
		bool gtsDirection = 0;
		bool characteristicType = 0;
			GtsGetCharacteristics(gtsCharacteristics, &gtsLength, &gtsDirection, 
								&characteristicType);
   printf("Tipo de mensagem: Requisição de GTS (0100) \n");
   printf("Nodo: %d \n", destAddr.shortAddress);
   printf("Tamanho do GTS: %d \n", gtsLength);
   printf("Sentido: %d \n", gtsDirection);
   printf("Característica: %d \n", characteristicType);
   gts_message->node_id=destAddr.shortAddress;
   gts_message->message_payload=(uint8_t) ((gtsCharacteristics && 00111111)<<2);

   payloadPointer =   call IEEE154TxBeaconPayload.setBeaconPayload(gts_message, sizeof(gts_message));
   printf("Mensagem adicionada a carga útil do beacon \n");
  }

  bool GtsGetDirection(uint8_t gtsCharacteristics)
  {
//0x10 = 00010000
    if ( (gtsCharacteristics & 0x10) == 0x10)
      return GTS_RX_DIRECTION;
    else
      return GTS_TX_DIRECTION;
  }  

  event void Boot.booted() 
  {
  	uint8_t payload =0;
    m_messageCount=0;
    m_payloadLen=strlen(&payload);
    payloadRegion=call Packet.getPayload(&m_frame, m_payloadLen);

    if (m_payloadLen <= call Packet.maxPayloadLength()){
      memcpy(payloadRegion, &payload, m_payloadLen);
      m_gotSlot=0;
      call MLME_RESET.request(TRUE);
    }  
    
  }

  event void MLME_RESET.confirm(ieee154_status_t status)
  {
    if (status != IEEE154_SUCCESS){
	printf("status != IEEE154_SUCCESS");
      return;
	}
    call MLME_SET.macShortAddress(COORDINATOR_ADDRESS);
    call MLME_SET.macAssociationPermit(FALSE);
    call MLME_SET.macGTSPermit(TRUE);  //RARS GTS
    call MLME_START.request(
                          PAN_ID,               // PANId
                          RADIO_CHANNEL,        // LogicalChannel
                          0,                    // ChannelPage,
                          0,                    // StartTime,
                          BEACON_ORDER,         // BeaconOrder
                          SUPERFRAME_ORDER,     // SuperframeOrder
                          TRUE,                 // PANCoordinator
                          FALSE,                // BatteryLifeExtension
                          FALSE,                // CoordRealignment
                          0,                    // CoordRealignSecurity,
                          0                     // BeaconSecurity
                        );
  }




  event message_t* MCPS_DATA.indication ( message_t* frame )
  {
    call Leds.led1Toggle();
    printf("MCPS_DATA.indication: %s \n" ,  frame);
    return frame;
  }

  event void MLME_START.confirm(ieee154_status_t status) {}

  event void MCPS_DATA.confirm(
                          message_t *msg,
                          uint8_t msduHandle,
                          ieee154_status_t status,
                          uint32_t Timestamp
                        ) { }

  event void IEEE154TxBeaconPayload.aboutToTransmit() {}

  event void IEEE154TxBeaconPayload.setBeaconPayloadDone(void *beaconPayload, uint8_t length) { }

  event void IEEE154TxBeaconPayload.modifyBeaconPayloadDone(uint8_t offset, void *buffer, uint8_t bufferLength) { }

  event void IEEE154TxBeaconPayload.beaconTransmitted() 
  {
    ieee154_macBSN_t beaconSequenceNumber = call MLME_GET.macBSN();
	printf("Sending beacon #: %hu \n" ,  beaconSequenceNumber);
    if (beaconSequenceNumber & 1)
      call Leds.led2On();
    else
      call Leds.led2Off();   
    if (m_gotSlot)
      post packetSendTask();




  }

  event void MLME_GTS.indication (
                          uint16_t DeviceAddress,
                          uint8_t GtsCharacteristics,
                          ieee154_security_t *security
                        )
  {
    if (GtsGetDirection(GtsCharacteristics) == GTS_RX_DIRECTION && m_gotSlot == 0)
    {
      post packetSendTask();
    
    }
  }

  event void MLME_GTS.confirm (
                          uint8_t GtsCharacteristics,
                          ieee154_status_t status
                        ){}
 event void MLME_ASSOCIATE.indication (
                          uint64_t DeviceAddress,
                          ieee154_CapabilityInformation_t CapabilityInformation,
                          ieee154_security_t *security
                        )
  {
  	printf("Pedido de associação recebido: \n");
    call MLME_ASSOCIATE.response(DeviceAddress, m_assignedShortAddress++, IEEE154_ASSOCIATION_SUCCESSFUL, 0);
  
}

  event void MLME_ASSOCIATE.confirm    (
                          uint16_t AssocShortAddress,
                          uint8_t status,
                          ieee154_security_t *security
                        ){
                        	  	unsigned char message[18];
                        	  	uint8_t* msg_pld_size;
                        	  	uint16_t tinyId = (AssocShortAddress && 0x0004);
                        	  	printf("Nodo: %d \n", AssocShortAddress);
                        	  	printf("Associação confirmada \n");
                        	  	printf("Encapsulando mensagem \n");
                        	  	message[0]=0;
                        	  	message[1]=0;
                        	  	message[2]=0;
                        	  	message[3]=1;
                        	  	printf("Tipo de mensagem: Des/Associação \n");
                        	  	message[4]=0;
                        	  	message[5]=0;
                        	  	message[6]=0;
                        	  	message[7]=0;
                        	  	message[8]=0;
                        	  	message[9]=1;
                        	  	message[10]=0;
                        	  	message[11]=1;
                        	  	msg_pld_size = (uint8_t*)&message[4];
                        	  	printf("Tamanho do payload: %d \n", *msg_pld_size);
								message[12]=1;
                        	  	printf("Caracteristica: Associação (1) \n");
                        	  	message[13]=(tinyId && 0b0000000000000001);
                        	  	message[14]=(tinyId && 0b0000000000000010);
                        	  	message[15]=(tinyId && 0b0000000000000100);
                        	  	message[16]=(tinyId && 0b0000000000001000);
                        	  	message[17]='\0';
                        	  	printf("Nodo: %d \n", tinyId);
                        	  	printf("Enviando mensagem de Associação de nodo para Serial \n", message);
                        	  	printf("%s \n", message);
                        	}
}





