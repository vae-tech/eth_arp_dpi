/* MTI_DPI */
#ifndef INCLUDED_ETH_HOST_BFM
#define INCLUDED_ETH_HOST_BFM

#ifdef __cplusplus
#define DPI_LINK_DECL  extern "C" 
#else
#define DPI_LINK_DECL 
#endif

#include "svdpi.h"

// test-bfm
DPI_LINK_DECL DPI_DLLESPEC
int
eth_dpi_main();

DPI_LINK_DECL DPI_DLLESPEC
int
host_tx_data_push(
    uint8_t buffer
);

DPI_LINK_DECL DPI_DLLESPEC
int
host_tx_transfer_init();

DPI_LINK_DECL int
host_delay(
    int nclk);

DPI_LINK_DECL DPI_DLLESPEC
void
host_rx_pkt_valid(
    int *npkt);

DPI_LINK_DECL DPI_DLLESPEC
void
host_rx_pkt_pull(
    int *pkt_len);

DPI_LINK_DECL DPI_DLLESPEC
void
host_rx_pkt_get_data(
    uint8_t *data_o,
    uint16_t index);

#endif // INCLUDED_ETH_HOST_BFM
