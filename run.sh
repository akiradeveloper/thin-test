mkdir -p data
HEXDUMP="hexdump -d"
TRACE=/sys/kernel/debug/tracing

# ----------------------------------------------------
# Config (on your own environment)
metadata_dev=/dev/mapper/hvg1-cache2g # metadata dev < 16GB (for what reason?)
data_dev=/dev/mapper/hvg2-back18g # data dev
data_block_size=128 # (128*N, N=1..16384) 64k-1g
low_water_mark=1
# ----------------------------------------------------

# Initialize function-graph tracer
echo function_graph > $TRACE/current_tracer
echo > $TRACE/trace
echo 1 > $TRACE/options/sym-addr
echo 1024 > $TRACE/buffer_size_kb
# echo 1 > $TRACE/events/block/enable
# echo 1 > $TRACE/events/syscalls/enable

echo > $TRACE/set_ftrace_filter
for fun in `ruby create_fun_list.rb`
do
    echo $fun >> $TRACE/set_ftrace_filter
done

# ----------------------------------------------------

# Need to zero the first 4k of metadata device 
# to indicate "empty" metadata.
# Metadata is 48 bytes for each data block.
dd if=/dev/zero of=$metadata_dev bs=4k count=1

# Create /dev/mapper/pool
echo > $TRACE/trace
dmsetup create pool --table "0 `blockdev --getsz $data_dev` thin-pool $metadata_dev $data_dev $data_block_size $low_water_mark"
cat $TRACE/trace > data/create-pool-ftrace
echo > $TRACE/trace

# Create a thin device
id0=0
echo > $TRACE/trace
dmsetup message /dev/mapper/pool 0 "create_thin $id0"
# Then activate
dmsetup create thin --table "0 16 thin /dev/mapper/pool $id0"
cat $TRACE/trace > data/create-thin-ftrace
echo > $TRACE/trace
$HEXDUMP /dev/mapper/thin > data/thin-dump # It's zeroed out on newly creating a thin dev

# ----------------------------------------------------

# Experiment 1
# See how Cow works (with ftrace)

# Create a snapshot (1->0)
# Need to suspend the parent thin device otherwise snapshot corrupts
id1=1
echo > $TRACE/trace
dmsetup suspend /dev/mapper/thin
dmsetup message /dev/mapper/pool 0 "create_snap $id1 $id0"
dmsetup resume /dev/mapper/thin
# Then activate
dmsetup create snap1 --table "0 16 thin /dev/mapper/pool $id1"
# echo 0 > $TRACE/tracing_on
cat $TRACE/trace > data/create-snap1-ftrace
echo > $TRACE/trace

echo > $TRACE/trace
dd if=/dev/urandom of=/dev/mapper/snap1 count=1
cat $TRACE/trace > data/snap1-cow-ftrace
echo > $TRACE/trace
$HEXDUMP /dev/mapper/snap1 > data/snap1-dump

# ----------------------------------------------------

# Experiment 2
# Recursive Snapshot

# Create a snapshot (2->1)
id2=2
dmsetup suspend /dev/mapper/thin
dmsetup message /dev/mapper/pool 0 "create_snap $id2 $id1"
dmsetup resume /dev/mapper/thin
# Then activate
dmsetup create snap2 --table "0 16 thin /dev/mapper/pool $id2"

dd if=/dev/urandom of=/dev/mapper/snap2 count=1
$HEXDUMP /dev/mapper/snap2 > data/snap2-dump

# Stop ftrace otherwise, the machine slow down (e.g. hard to edit a file in vim)
echo noop > $TRACE/trace
