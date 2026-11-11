# SPDX-License-Identifier: EUPL-1.2
# The device tree keeps 300 MB free in product for Google apps flashed afterwards.
# Here they are built in, and with that much kept free the partitions no longer
# fit in super.
BOARD_PRODUCTIMAGE_PARTITION_RESERVED_SIZE := 100000000
