# BLE Scanner - Control de Collares ENKOA

Aplicación de línea de comandos para conectarse a dispositivos Bluetooth Low Energy (BLE) ENKOA y enviar comandos específicos.

## 📋 Requisitos

### Para ejecutar el binario compilado:
- **macOS** (utiliza el framework CoreBluetooth)
- **Permisos de Bluetooth** habilitados para la terminal
- ✅ **NO necesitas Go instalado**
- ✅ **NO necesitas dependencias externas**

### Para compilar desde código fuente:
- **macOS** (utiliza el framework CoreBluetooth a través de go-ble/darwin)
- **Go 1.16+** instalado

## 🚀 Instalación desde Cero

### 1. Instalar Go (si no lo tienes)

```bash
# Usando Homebrew
brew install go

# Verificar instalación
go version
```

### 2. Clonar o crear el proyecto

```bash
mkdir -p ~/Projects/ble-scanner
cd ~/Projects/ble-scanner
```

### 3. Inicializar el módulo Go

```bash
go mod init ble-scanner
```

### 4. Instalar dependencias

```bash
go get github.com/go-ble/ble
go get github.com/go-ble/ble/darwin
```

### 5. Compilar el programa

**Compilación estándar:**
```bash
go build -o ble-scanner main.go
```

**Compilación optimizada (recomendado):**
```bash
go build -ldflags="-s -w" -o ble-scanner main.go
```

El flag `-ldflags="-s -w"` reduce el tamaño del ejecutable eliminando información de debug.

### 6. Mover el ejecutable (opcional)

```bash
# Crear directorio para el binario
mkdir -p ./bin

# Mover el ejecutable
mv ble-scanner ./bin/

# O instalarlo globalmente
sudo mv ble-scanner /usr/local/bin/
```

## 🎯 Uso

### Sintaxis básica

```bash
./ble-scanner <nombre_parcial_dispositivo> <comando_hex>
```

### Ejemplos

**Enviar melodía 2 (Tetris):**
```bash
./ble-scanner "3839303553316E10" "03"
```

**Resetear el collar:**
```bash
./ble-scanner "3839303553316E10" "22"
```

**Buscar por parte del nombre:**
```bash
./ble-scanner "383930" "04"
```

### Comandos disponibles

| Comando | Descripción |
|---------|-------------|
| `02` | Melodía 1 (Pacman) |
| `03` | Melodía 2 (Tetris) |
| `04` | Melodía 3 (Nokia) |
| `07` | Melodía 4 (Zelda) |
| `22` | Reset firmware |

## 🔧 Cómo Funciona

### Arquitectura del Programa

```
┌─────────────────────────────────────────────────┐
│  1. ARGUMENTOS                                  │
│     - Nombre parcial del dispositivo           │
│     - Comando hexadecimal a enviar             │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  2. INICIALIZACIÓN BLE                          │
│     - Configura adaptador Bluetooth (darwin)   │
│     - Valida permisos                           │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  3. ESCANEO (max 2 minutos)                     │
│     - Busca dispositivos BLE activos           │
│     - Filtra por nombre parcial                │
│     - Evita duplicados con mapa de procesados  │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  4. CONEXIÓN (3 intentos)                       │
│     - Conecta al dispositivo encontrado        │
│     - Timeout: 30 segundos por intento         │
│     - Espera 5s entre reintentos               │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  5. DESCUBRIMIENTO DE SERVICIOS                 │
│     - Obtiene perfil BLE completo              │
│     - Busca servicio ENKOA (UUID específico)   │
│     - Identifica característica de escritura   │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  6. ENVÍO DE COMANDO                            │
│     - Convierte hex a byte                     │
│     - Escribe en característica [0]            │
│     - Intenta sin/con respuesta (fallback)     │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  7. FINALIZACIÓN                                │
│     - Espera 2 segundos                        │
│     - Cierra conexión BLE                      │
│     - Termina el escaneo                       │
└─────────────────────────────────────────────────┘
```

### Detalles Técnicos

#### 1. **Escaneo BLE**
- Utiliza `ble.Scan()` con modo activo
- Filtra por nombre parcial (case-insensitive)
- Usa un mapa `processedDevices` para evitar procesar el mismo dispositivo múltiples veces durante los advertisement packets

#### 2. **Conexión**
- Timeout de 30 segundos por intento
- Máximo 3 intentos con 5 segundos entre cada uno
- Espera inicial de 2 segundos para estabilizar la conexión BLE

#### 3. **Servicio ENKOA**
- **UUID del Servicio:** `0000fe40-cc7a-482a-984a-7f2ed5b3e58f`
- **Característica usada:** `characteristics[0]` (primera característica)
- **Normalización de UUIDs:** Remueve guiones antes de comparar (compatibilidad entre plataformas)

#### 4. **Escritura del Comando**
- Primero intenta **write without response** (más rápido)
- Si falla, intenta **write with response** (más confiable)
- Convierte el comando hex (string) a byte antes de enviar

#### 5. **Ejecución Asíncrona**
- La conexión y envío se ejecutan en una goroutine
- El escaneo continúa hasta que se conecta exitosamente o se cumple el timeout
- Se cancela el contexto para detener el escaneo después del envío

## ⚠️ Consideraciones

### Permisos en macOS

macOS puede requerir permisos de Bluetooth. Si el ejecutable no funciona:

1. Ve a **Configuración del Sistema** > **Privacidad y Seguridad** > **Bluetooth**
2. Agrega la Terminal o tu aplicación de terminal (iTerm2, etc.) a la lista
3. Reinicia la terminal

### Limitaciones

- **Solo macOS:** Usa el framework `darwin` (CoreBluetooth)
- **Sin pairing:** No requiere emparejar el dispositivo previamente
- **Timeout fijo:** 2 minutos para encontrar el dispositivo
- **Un dispositivo a la vez:** Se detiene después de enviar el comando al primer dispositivo que coincida

## 🐛 Troubleshooting

### "Error: context deadline exceeded"
- El dispositivo está fuera de rango o apagado
- Intenta acercar el dispositivo
- Verifica que el collar tenga batería

### "Error: Writing is not permitted"
- Problema de permisos de macOS
- Verifica los permisos de Bluetooth en Configuración del Sistema
- Algunos dispositivos pueden requerir pairing (no debería ser el caso con ENKOA)

### "Error: connect failed: aborted"
- Múltiples conexiones simultáneas (ya resuelto con el mapa de procesados)
- Interferencia Bluetooth
- Intenta de nuevo

### El collar no reacciona
- Verifica que el comando hex sea correcto
- El collar puede estar en modo de ahorro de energía
- Intenta con otro comando (e.g., `03` para melodía)

## 📦 Estructura del Código

```
main.go
├── const
│   ├── ENKOA_SERVICE_UUID    # UUID del servicio BLE
│   ├── SCAN_DURATION         # Tiempo máximo de escaneo (2 min)
│   └── CONNECT_TIMEOUT       # Timeout de conexión (30s)
├── main()
│   ├── Validación de argumentos
│   ├── Inicialización BLE (darwin.NewDevice)
│   ├── Escaneo con filtrado
│   └── Goroutine de conexión
│       ├── Intentos de conexión (3x)
│       ├── Descubrimiento de servicios
│       ├── Búsqueda del servicio ENKOA
│       ├── Envío del comando
│       └── Limpieza y cierre
```

## 📝 Notas de Desarrollo

### Dependencias principales

```go
github.com/go-ble/ble         // API de Bluetooth LE
github.com/go-ble/ble/darwin  // Implementación para macOS
```

### Actualizar dependencias

```bash
go get -u github.com/go-ble/ble
go mod tidy
```

### Desarrollo

Para desarrollo activo, usa `go run`:

```bash
go run main.go "3839303553316E10" "22"
```

### Testing

Prueba diferentes comandos para verificar la funcionalidad:

```bash
# Melodía (debería sonar)
./ble-scanner "3839303553316E10" "03"

# Reset (debería reiniciar el collar)
./ble-scanner "3839303553316E10" "22"
```

## 📄 Licencia

Este proyecto es para uso interno. No redistribuir sin autorización.

## 🤝 Contribuciones

Para cambios o mejoras:
1. Documenta cualquier cambio en el protocolo BLE
2. Mantén la compatibilidad con el servicio ENKOA
3. Actualiza este README con nuevos comandos o características

---

**Autor:** Desarrollado para control de collares ENKOA  
**Última actualización:** Febrero 2026
