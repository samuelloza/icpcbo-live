# ICPC Bolivia ISO

Repositorio para construir la ISO Debian personalizada del entorno ICPC Bolivia.

# Quiero probar el ultimo Release sin tener que compilar
En el siguiente drive se subira los ultimos isos, actualmente tenemos disponible para escritorios Gnome y Xfce 4

[Link del drive](https://drive.google.com/drive/folders/1V4aotPbnwvc3KpIkdwUbIUNvwZ3ggsdO)

## Requisitos

Los comandos de build usan `debootstrap`, `chroot`, mounts y generación de ISO, por eso deben ejecutarse en Linux y normalmente con `sudo`.

En Debian/Ubuntu instala:

```bash
sudo apt update
sudo apt install -y \
  bash \
  ca-certificates \
  coreutils \
  curl \
  debootstrap \
  dosfstools \
  file \
  gdisk \
  grub-common \
  grub-pc-bin \
  grub-efi-amd64-bin \
  initramfs-tools \
  kmod \
  mtools \
  rsync \
  squashfs-tools \
  systemd-sysv \
  xorriso \
  xz-utils \
  zstd
```

Para usar el cache local de APT:

```bash
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
```

Para probar la ISO con VM desde `start.sh`:

```bash
sudo apt install -y \
  bridge-utils \
  qemu-kvm \
  qemu-system-x86 \
  qemu-utils \
  virtinst \
  libvirt-daemon-system \
  libvirt-clients \
  libguestfs-tools \
  virt-manager \
  virt-viewer

sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm "$USER"
sudo virsh net-start default
sudo virsh net-autostart default
```

Después de agregar el usuario a `libvirt,kvm`, cierra sesión y vuelve a entrar
para que los grupos se apliquen.

Para probar el flujo con la VM Windows XP usada por `start.sh`, descarga el
disco desde:

```text
https://drive.google.com/file/d/12x75O6I0UPZTPSoJaXKCjkYmDoMlN7CI/view?usp=drivesdk
```

Guárdalo en la raíz del repo y renómbralo

```bash
mv MicroXP.qcow2 "Windows XP.qcow2"
```

La VM creada por `start.sh` se llama `icpc-winxp-lab`. Para abrirla o revisarla:

```bash
sudo virsh list --all
virt-viewer --connect qemu:///system icpc-winxp-lab
```

## Configuración

La configuración central está en:

```text
config/iso.conf
```

## Build

Construir la ISO completa:

```bash
sudo ./start.sh build
```

Construir y levantar la VM de prueba:

```bash
sudo ./start.sh build-run
```

## ISOs por región

Un ISO por región (La Paz, El Alto, Sucre, ...), cada uno con su `REGION_ID`.
El id va en el nombre del archivo (`<id>-20260901222621.iso`), en
`/etc/contestiso/region.env`, en `/etc/issue` y en `os-release` (`VARIANT_ID`).
Si no se define `GROUP_ID`, se usa `REGION_ID` como identidad ante el
control-server.

Una sola región (env var):

```bash
REGION_ID=lapaz REGION_NAME="La Paz" sudo -E ./scripts/build.sh seed
```

Todas de una, desde un archivo:

```bash
cp config/regions.conf.example config/regions.conf   # editá id | Nombre | enroll_token
sudo ./scripts/build-regions.sh                      # un ISO por línea
```

`config/regions.conf` está gitignored (puede llevar enroll tokens). El primer
build hace debootstrap + paquetes; los siguientes reusan el caché del rootfs
base y solo repiten squashfs + ISO.

## Escritorio

Por defecto se construye GNOME:

```bash
sudo ./start.sh build
```

Para XFCE:

```bash
DESKTOP_PROFILE=xfce4 sudo -E ./start.sh build
```

Los hooks y paquetes están separados así:

```text
scripts/setup.d/common/
scripts/setup.d/gnome/
scripts/setup.d/xfce4/
```
