package main

import (
	"context"
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

func main() {
	// Verificar argumentos
	if len(os.Args) < 3 {
		fmt.Println("Uso: go run main.go <nombre_parcial> <comando_hex>")
		fmt.Println("Ejemplo: go run main.go \"3839303553316E10\" \"03\"")
		fmt.Println("\nComandos disponibles:")
		fmt.Println("  02 - Melodía 1 (Pacman)")
		fmt.Println("  03 - Melodía 2 (Tetris)")
		fmt.Println("  04 - Melodía 3 (Nokia)")
		fmt.Println("  07 - Melodía 4 (Zelda)")
		fmt.Println("  22 - Reset firmware")
		os.Exit(1)
	}
	
	searchFilter := strings.ToLower(os.Args[1])
	commandHex := os.Args[2]
	
	// Inicializar adaptador Bluetooth para macOS
	d, err := darwin.NewDevice()
	if err != nil {
		log.Fatalf("Error al inicializar Bluetooth: %v\n", err)
	}
	ble.SetDefaultDevice(d)

	fmt.Printf("🔍 Buscando dispositivos Bluetooth LE...\n")
	fmt.Printf("🎯 Servicio ENKOA: %s\n", ENKOA_SERVICE_UUID)
	fmt.Printf("🔎 Buscando nombre que contenga: '%s'\n", searchFilter)
	fmt.Printf("📤 Comando a enviar: 0x%s\n\n", commandHex)

	// Crear contexto con timeout
	ctx, cancel := context.WithTimeout(context.Background(), SCAN_DURATION)
	defer cancel()

	// Mapa para controlar dispositivos ya procesados
	processedDevices := make(map[string]bool)
	
	// Escanear dispositivos
	err = ble.Scan(ctx, true, func(a ble.Advertisement) {
		addr := a.Addr().String()
		name := a.LocalName()
		
		// Filtrar solo por nombre
		if !strings.Contains(strings.ToLower(name), searchFilter) {
			return
		}
		
		// Evitar procesar el mismo dispositivo múltiples veces
		if processedDevices[addr] {
			return
		}
		processedDevices[addr] = true
		
		fmt.Printf("📱 Dispositivo encontrado: %s\n", name)
		fmt.Printf("   Dirección: %s\n", addr)
		fmt.Printf("   RSSI: %d dBm\n\n", a.RSSI())
			
		fmt.Printf("═══════════════════════════════════\n")
		fmt.Printf("⚡ Conectando al dispositivo...\n\n")
		
		// Conectar en goroutine
		go func(deviceAddr string, cmdHex string) {
			// Delay para estabilizar
			time.Sleep(2 * time.Second)
			
			maxAttempts := 3
			for attempt := 1; attempt <= maxAttempts; attempt++ {
				fmt.Printf("🔄 Intento %d/%d\n", attempt, maxAttempts)
				
				connectCtx, connectCancel := context.WithTimeout(context.Background(), CONNECT_TIMEOUT)
				client, err := ble.Dial(connectCtx, ble.NewAddr(deviceAddr))
				
				if err != nil {
					fmt.Printf("   ❌ Error: %v\n", err)
					connectCancel()
					if attempt < maxAttempts {
						time.Sleep(5 * time.Second)
					}
					continue
				}
				
				fmt.Printf("   ✅ Conectado!\n\n")
				
				// Descubrir servicios
				profile, err := client.DiscoverProfile(true)
				if err != nil {
					fmt.Printf("   ❌ Error al descubrir servicios: %v\n", err)
					client.CancelConnection()
					connectCancel()
					cancel()
					return
				}
				
				// Buscar servicio ENKOA
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
					cancel()
					return
				}
				
				// Enviar comando
				var cmdByte byte
				fmt.Sscanf(cmdHex, "%02x", &cmdByte)
				
				char := enkoaService.Characteristics[0]
				commandData := []byte{cmdByte}
				
				fmt.Printf("   📤 Enviando comando 0x%02X...\n", cmdByte)
				err = client.WriteCharacteristic(char, commandData, false)
				
				if err != nil {
					err = client.WriteCharacteristic(char, commandData, true)
				}
				
				if err != nil {
					fmt.Printf("   ❌ Error: %v\n", err)
				} else {
					fmt.Printf("   ✅ Comando enviado!\n")
					time.Sleep(2 * time.Second)
				}
				
				client.CancelConnection()
				connectCancel()
				fmt.Printf("═══════════════════════════════════\n\n")
				cancel()
				return
			}
			
			fmt.Printf("❌ No se pudo conectar\n")
			fmt.Printf("═══════════════════════════════════\n\n")
			cancel()
		}(addr, commandHex)
	}, nil)

	if err != nil && err != context.DeadlineExceeded && err != context.Canceled {
		fmt.Fprintf(os.Stderr, "❌ Error durante escaneo: %v\n", err)
		os.Exit(1)
	}
	
	fmt.Println("✅ Proceso completado")
}
