package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/go-ble/ble"
	"github.com/go-ble/ble/darwin"
)

const (
	// UUID del servicio ENKOA
	ENKOA_SERVICE_UUID = "0000fe40-cc7a-482a-984a-7f2ed5b3e58f"
	// Duración del escaneo
	SCAN_DURATION = 2 * time.Minute
	// Timeout de conexión
	CONNECT_TIMEOUT = 30 * time.Second
)

type DeviceEntry struct {
	Name   string `json:"name"`
	DevEUI string `json:"devEui"`
}

func loadDevicesFromJSON(path string) ([]DeviceEntry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var devices []DeviceEntry
	if err := json.Unmarshal(data, &devices); err != nil {
		return nil, err
	}
	return devices, nil
}

func main() {
	// Verificar argumentos
	if len(os.Args) < 3 {
		fmt.Println("Uso: ble-scanner <devEUI|archivo.json> <comando_hex>")
		fmt.Println("Ejemplo (un dispositivo):  ble-scanner \"3839303553316E10\" \"03\"")
		fmt.Println("Ejemplo (múltiples):       ble-scanner \"./devices.json\" \"22\"")
		fmt.Println("\nComandos disponibles:")
		fmt.Println("  02 - Melodía 1 (Pacman)")
		fmt.Println("  03 - Melodía 2 (Tetris)")
		fmt.Println("  04 - Melodía 3 (Nokia)")
		fmt.Println("  07 - Melodía 4 (Zelda)")
		fmt.Println("  22 - Reset firmware")
		os.Exit(1)
	}

	arg1 := os.Args[1]
	commandHex := os.Args[2]

	// Construir lista de filtros de búsqueda (devEUIs) y mapa devEUI -> nombre
	var searchFilters []string
	devEuiToName := make(map[string]string)

	if strings.HasSuffix(strings.ToLower(arg1), ".json") {
		devices, err := loadDevicesFromJSON(arg1)
		if err != nil {
			log.Fatalf("Error al leer el archivo JSON: %v\n", err)
		}
		for _, d := range devices {
			key := strings.ToLower(d.DevEUI)
			searchFilters = append(searchFilters, key)
			devEuiToName[key] = d.Name
		}
		fmt.Printf("📋 Cargados %d dispositivos desde %s\n", len(searchFilters), arg1)
	} else {
		key := strings.ToLower(arg1)
		searchFilters = []string{key}
		devEuiToName[key] = arg1
	}

	// Inicializar adaptador Bluetooth para macOS
	d, err := darwin.NewDevice()
	if err != nil {
		log.Fatalf("Error al inicializar Bluetooth: %v\n", err)
	}
	ble.SetDefaultDevice(d)

	fmt.Printf("🔍 Buscando dispositivos Bluetooth LE...\n")
	fmt.Printf("🎯 Servicio ENKOA: %s\n", ENKOA_SERVICE_UUID)
	fmt.Printf("📤 Comando a enviar: 0x%s\n\n", commandHex)

	// Crear contexto con timeout para el escaneo
	ctx, cancel := context.WithTimeout(context.Background(), SCAN_DURATION)
	defer cancel()

	type discoveredDevice struct {
		addr          string
		bleLocalName  string
		matchedFilter string
		friendlyName  string
	}

	// Cola con capacidad para todos los dispositivos esperados
	queue := make(chan discoveredDevice, len(searchFilters))

	// Mapa para no encolar el mismo dispositivo BLE más de una vez
	seen := make(map[string]bool)

	// Conjunto de devEUIs pendientes de descubrir
	pending := make(map[string]bool)
	for _, f := range searchFilters {
		pending[f] = true
	}

	// Worker: procesa conexiones una por una, secuencialmente
	done := make(chan struct{})
	go func() {
		defer close(done)
		processed := 0
		for dev := range queue {
			fmt.Printf("═══════════════════════════════════\n")
			fmt.Printf("⚡ Conectando a %s", dev.bleLocalName)
			if dev.friendlyName != "" && !strings.EqualFold(dev.friendlyName, dev.bleLocalName) {
				fmt.Printf(" (%s)", dev.friendlyName)
			}
			fmt.Printf("...\n\n")

			maxAttempts := 3
			for attempt := 1; attempt <= maxAttempts; attempt++ {
				fmt.Printf("🔄 Intento %d/%d para %s\n", attempt, maxAttempts, dev.addr)

				connectCtx, connectCancel := context.WithTimeout(context.Background(), CONNECT_TIMEOUT)
				client, err := ble.Dial(connectCtx, ble.NewAddr(dev.addr))

				if err != nil {
					fmt.Printf("   ❌ Error: %v\n", err)
					connectCancel()
					if attempt < maxAttempts {
						time.Sleep(5 * time.Second)
					}
					continue
				}

				fmt.Printf("   ✅ Conectado!\n\n")

				profile, err := client.DiscoverProfile(true)
				if err != nil {
					fmt.Printf("   ❌ Error al descubrir servicios: %v\n", err)
					client.CancelConnection()
					connectCancel()
					break
				}

				var enkoaService *ble.Service
				normalizedEnkoaUUID := strings.ToLower(strings.ReplaceAll(ENKOA_SERVICE_UUID, "-", ""))
				for _, service := range profile.Services {
					normalizedServiceUUID := strings.ToLower(strings.ReplaceAll(service.UUID.String(), "-", ""))
					if normalizedServiceUUID == normalizedEnkoaUUID {
						enkoaService = service
						break
					}
				}

				if enkoaService == nil || len(enkoaService.Characteristics) == 0 {
					fmt.Printf("   ❌ Servicio ENKOA no encontrado\n")
					client.CancelConnection()
					connectCancel()
					break
				}

				var cmdByte byte
				fmt.Sscanf(commandHex, "%02x", &cmdByte)
				char := enkoaService.Characteristics[0]
				commandData := []byte{cmdByte}

				fmt.Printf("   📤 Enviando comando 0x%02X...\n", cmdByte)
				err = client.WriteCharacteristic(char, commandData, false)
				if err != nil {
					err = client.WriteCharacteristic(char, commandData, true)
				}

				if err != nil {
					fmt.Printf("   ❌ Error al enviar: %v\n", err)
				} else {
					fmt.Printf("   ✅ Comando enviado a %s!\n", dev.addr)
					time.Sleep(2 * time.Second)
				}

				client.CancelConnection()
				connectCancel()
				break
			}

			fmt.Printf("═══════════════════════════════════\n\n")

			processed++
			if processed == len(searchFilters) {
				// Todos procesados, detener el escaneo
				cancel()
			}
		}
	}()

	// Escaneo continuo: descubre dispositivos y los encola según se van encontrando
	err = ble.Scan(ctx, true, func(a ble.Advertisement) {
		addr := a.Addr().String()
		name := strings.ToLower(a.LocalName())

		matchedFilter := ""
		for _, f := range searchFilters {
			if strings.Contains(name, f) {
				matchedFilter = f
				break
			}
		}
		if matchedFilter == "" {
			return
		}

		if seen[addr] {
			return
		}
		seen[addr] = true
		delete(pending, matchedFilter)

		friendlyName := devEuiToName[matchedFilter]
		fmt.Printf("📱 Descubierto: %s", a.LocalName())
		if friendlyName != "" && !strings.EqualFold(friendlyName, a.LocalName()) {
			fmt.Printf(" (%s)", friendlyName)
		}
		fmt.Printf(" → en cola (%d pendientes de descubrir)\n", len(pending))

		queue <- discoveredDevice{
			addr:          addr,
			bleLocalName:  a.LocalName(),
			matchedFilter: matchedFilter,
			friendlyName:  friendlyName,
		}
	}, nil)

	// Cerrar la cola para que el worker sepa que no llegará nada más
	close(queue)

	// Esperar a que el worker termine de procesar todo
	<-done

	if err != nil && err != context.DeadlineExceeded && err != context.Canceled {
		fmt.Fprintf(os.Stderr, "❌ Error durante escaneo: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("✅ Proceso completado")
}
