#!/bin/bash

libscuda_path="$(pwd)/libscuda.so"
client_path="$(pwd)/client.cpp $(pwd)/codegen/gen_client.cpp"
server_path="$(pwd)/server.cu $(pwd)/codegen/gen_server.cu"
server_out_path="$(pwd)/server.so"

build() {
  echo "building client..."

  if [[ "$(uname)" == "Linux" ]]; then
    gcc -c -fPIC "$(pwd)/client.cpp" -o "$(pwd)/client.o" -I/usr/local/cuda/include
    gcc -c -fPIC "$(pwd)/codegen/gen_client.cpp" -o "$(pwd)/codegen/gen_client.o" -I/usr/local/cuda/include

    echo "linking client files..."

    gcc -shared -o libscuda.so "$(pwd)/client.o" "$(pwd)/codegen/gen_client.o" -L/usr/local/cuda/lib64 -lcudart -lstdc++

  else
    echo "No compiler options set for os "$(uname)""
  fi

  if [ ! -f "$libscuda_path" ]; then
    echo "libscuda.so not found. build may have failed."
    exit 1
  fi
}

server() {
  echo "building server..." 

  if [[ "$(uname)" == "Linux" ]]; then
    nvcc -o $server_out_path $server_path -lnvidia-ml -lcuda
  else
    echo "No compiler options set for os "$(uname)""
  fi

  echo "starting server... $server_out_path"

  "$server_out_path"
}

run() {
  build

  LD_PRELOAD="$libscuda_path" python3 -c "import torch; print(torch.cuda.is_available())"
}

# Main script logic using a switch case
case "$1" in
  build)
      build
      ;;
  run)
      run
      ;;
  server)
      server
      ;;
  *)
      echo "Usage: $0 {build|run|server}"
      exit 1
      ;;
esac