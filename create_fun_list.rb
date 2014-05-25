KERNELROOT="/home/akira/linux-2.6"
DM = KERNELROOT + "/drivers/md"

t = `nm #{DM}/dm-thin.o #{DM}/dm-thin-metadata.o #{DM}/persistent-data/*.o`
  .split("\n")
  .map { |line| line.split }
  .select { |x| x.size == 3 }
  .select { |x| x[1] == "t" }
  .map { |x| x[2] }
  .join "\n"

$stdout << t
