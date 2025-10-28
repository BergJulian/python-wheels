repo="$PWD"
base="$repo/ns-3"

section ---------------- install ----------------
run apt-get update
run apt-get install -y --no-install-recommends \
 	bzip2 \
 	cmake \
 	curl \
 	g++ \
 	git \
 	libclang-dev \
 	llvm-dev \
 	make \
 	patch \
 	patchelf \
 	python3-dev \
 	python3-pip \
 	python3-setuptools \
 	python3-wheel \
 	qtbase5-dev \
	libboost-dev \
	libboost-system-dev \
	libboost-thread-dev \
 	ninja-build \
 	zip \
	&& true

export NS3_VERSION=3.45
export NS3_PYTHON_VERSION=3.11

ns3_sha1=9b0bc3c3a35ec17e9afabbff86e3c1eef1d5fc91
ns_allinone_sha1=b47774dd89ec770a3bc88cf95251319aa0266afc

section ---------------- download ----------------
workdir /opt/ns-3
run curl -L -o ../ns-allinone-$NS3_VERSION.tar.bz2 https://www.nsnam.org/releases/ns-allinone-$NS3_VERSION.tar.bz2
runsh "echo '${ns_allinone_sha1} ../ns-allinone-$NS3_VERSION.tar.bz2' | sha1sum -c"
run tar xj --strip-components 1 -f ../ns-allinone-$NS3_VERSION.tar.bz2

section ---------------- NetAnim ----------------
for d in netanim-*; do
  [ -d "$d" ] || continue
  mkdir -p "$d/build"
  pushd "$d/build" >/dev/null
  cmake .. -G "Unix Makefiles"
  cmake --build . -- -j"$(nproc)"
  find . -type f -name 'netanim' -executable -exec cp {} /ns-3-build/usr/local/bin/ \;
  popd >/dev/null
done

section ---------------- ns-3 build ----------------
workdir /opt/ns-3/ns-$NS3_VERSION
run mkdir build
workdir /opt/ns-3/ns-$NS3_VERSION/build
run cmake -G Ninja \
    -DNS3_PYTHON_BINDINGS=ON \
    -DNS3_EXAMPLES=ON \
    -DNS3_TESTS=ON \
    -DPYTHON_EXECUTABLE=/usr/bin/python${NS3_PYTHON_VERSION} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/ns-3-build/usr/local \
	-DNS3_WARNINGS_AS_ERRORS=OFF \
    ..
run ninja
run ninja install

run mkdir -p /ns-3-build/usr/local/lib/python${NS3_PYTHON_VERSION}/site-packages
run cp -r /opt/ns-3/ns-$NS3_VERSION/build/bindings/python/ns /ns-3-build/usr/local/lib/python${NS3_PYTHON_VERSION}/site-packages/

section ---------------- python wheel ----------------
run mkdir -p /opt/ns
workdir /opt/ns

run cp -r "$repo/ns-3/ns" /opt/ns/
run cp "$repo/ns-3/ns/setup.py" /opt/ns/
run cp -r "/opt/ns-3/ns-$NS3_VERSION/build/bindings/python/ns" /opt/ns

ns3_patch="patch/ns-$NS3_VERSION"
run rm -rf "$ns3_patch"
run mkdir -p "$ns3_patch/ns/_/lib" "$ns3_patch/ns/_/bin"

run find /ns-3-build/usr/local/lib -maxdepth 1 -type f \( -name 'libns3*' -o -name '*.so*' -o -name '*.so' \) -exec cp -P '{}' "$ns3_patch/ns/_/lib/" \; || true
run find /ns-3-build -type f -name '*.so*' -exec cp -P '{}' "$ns3_patch/ns/_/lib/" \; || true
run find /ns-3-build/usr/local/bin -type f -exec cp '{}' "$ns3_patch/ns/_/bin/" \; || true

run mkdir -p "$ns3_patch/ns"
run cp -r /opt/ns/ns /opt/ns/setup.py "$ns3_patch/ns/"
run cp /ns-3-build/usr/local/lib/python$NS3_PYTHON_VERSION/site-packages/ns/__init__.py "$ns3_patch/ns/" || true

run mkdir -p /tmp/ns-wheel
run cp -r /opt/ns/ns /opt/ns/setup.py /tmp/ns-wheel/
workdir /tmp/ns-wheel
run python3 setup.py bdist_wheel

run python3 -m wheel unpack -d /tmp/ns-wheel-unpack "dist/ns-$NS3_VERSION-py3-none-any.whl" || python3 -m wheel unpack -d /tmp/ns-wheel-unpack dist/*.whl

run unpack_dir="/tmp/ns-wheel-unpack/ns-$NS3_VERSION" && mkdir -p "$unpack_dir/ns/_/lib" "$unpack_dir/ns/_/bin" || true

run find /ns-3-build/usr/local/lib -type f \( -name 'libns3*' -o -name '*.so*' -o -name '*.so' \) -exec cp -P '{}' "$unpack_dir/ns/_/lib/" \; || true
run find /ns-3-build -type f -name '*.so*' -exec cp -P '{}' "$unpack_dir/ns/_/lib/" \; || true
run find /ns-3-build/usr/local/bin -type f -exec cp '{}' "$unpack_dir/ns/_/bin/" \; || true

run rm -rf "$unpack_dir/ns/_/lib/python$NS3_PYTHON_VERSION" || true

run for f in "$unpack_dir"/ns/*.so; do [ -f "$f" ] || continue; patchelf --set-rpath '$ORIGIN/_/lib' "$f" || true; done
run for f in "$unpack_dir"/ns/_/bin/*; do [ -f "$f" ] || continue; patchelf --set-rpath '$ORIGIN/../lib' "$f" || true; chmod +x "$f" || true; done
run for f in "$unpack_dir"/ns/_/lib/*.so*; do [ -f "$f" ] || continue; patchelf --set-rpath '$ORIGIN' "$f" || true; done

run mkdir -p dist2
run python3 -m wheel pack -d dist2 "$unpack_dir"

asset_path="$base/ns-$NS3_VERSION-py3-none-linux_x86_64.whl"
run cp "dist2/ns-$NS3_VERSION-py3-none-any.whl" "$asset_path"

section ---------------- asset ----------------
asset "$asset_path"

