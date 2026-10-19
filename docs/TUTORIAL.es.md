# Tutorial de BLEScoreboard

Cómo vincular tu marcador y dirigir un partido con la app. El mismo recorrido está dentro de la app: toca el botón **?**.

> Las capturas se generan con el modo demo de depuración de la app (`-demo scanning|list|connected|connected-bottom`), por eso usan datos de ejemplo. [English version](TUTORIAL.md)

## 1. Encuentra tu marcador

Enciende el marcador y abre la app. El radar busca marcadores cercanos y el LED del marcador **parpadea en azul** mientras espera a tu teléfono. Mantén el Bluetooth activado y el teléfono cerca.

<img src="images/1-scan-es.png" width="280" alt="Buscando marcadores con la tarjeta de ayuda">

Si el Bluetooth está apagado, la pantalla te lo indica en lugar de mostrar el radar.

## 2. Vincúlalo

Los marcadores aparecen en la lista al encontrarse y la app sigue buscando más. Toca **Vincular marcador** junto a tu marcador; si hay varias canchas, elige el nombre que le diste. El LED se pone **verde fijo** cuando estás conectado.

<img src="images/2-link-es.png" width="280" alt="Lista de marcadores encontrados">

## 3. Dirige el partido

La tarjeta superior muestra el estado de la conexión, la batería del marcador y su nombre. Debajo están los nombres de los equipos, los botones de puntos y el reloj. **Iniciar**, **Pausar** y **Reiniciar reloj** controlan la cuenta regresiva, y el control de minutos define la duración del periodo. El reloj corre en tu teléfono, así que el partido continúa aunque se pierda la conexión. Cuando el marcador vuelve, la app se reconecta y reenvía el estado actual.

<img src="images/3-game-es.png" width="280" alt="Puntos, reloj y configuración del partido">

## 4. Configura el partido

Elige el periodo actual, el total de periodos y el brillo del panel. En la tarjeta superior puedes cambiar el nombre del periodo (por ejemplo Cuarto, Mitad o Tiempo) y darle un nombre al marcador con **Cambiar**: el marcador lo guarda, se reinicia y se vuelve a vincular. Los nombres usan solo caracteres simples (de 1 a 20) y el panel muestra los nombres de los equipos sin acentos.

<img src="images/4-setup-es.png" width="280" alt="Periodo, total de periodos y brillo">

## 5. Elige los colores del panel

Toca **Colores del panel** en la tarjeta superior. Elige el color del reloj (en marcha y detenido), el periodo, el nombre y los puntos de cada equipo, y las dos alertas de inicio, con las muestras o con cualquier color del selector. La vista previa de arriba muestra el panel mientras eliges. El marcador guarda los colores y la app los envía de nuevo cada vez que te conectas. Usa el interruptor de una fila para **ocultar** ese elemento en el panel (el interruptor del reloj lo oculta tanto en marcha como detenido); una alerta apagada no se reproduce. La vista previa y el marcador simulado lo ocultan al instante. **Restablecer colores** vuelve a los colores predeterminados y deja los interruptores como están.

<img src="images/5-colors-es.png" width="280" alt="Página de colores del panel con vista previa en vivo">

## 6. Alertas de inicio

Cuando empieza un partido (periodo 1) o un periodo posterior, el panel hace parpadear su borde y desplaza `INICIO PARTIDO` o `PERIODO 2` por la pantalla a triple tamaño, en el color de la alerta, y luego vuelve al marcador. La alerta suena cuando el reloj arranca desde la duración completa del periodo; al reanudar tras una pausa no se repite. En la página de colores, **Probar alerta de inicio** y **Probar alerta de periodo** las prueban en la vista previa y en tu marcador.

<img src="images/6-alerts-es.png" width="280" alt="Una alerta de inicio reproduciéndose en la vista previa del panel">

<img src="images/alert-game-start.gif" width="420" alt="Animación de la alerta de inicio del partido en el panel"> <img src="images/alert-period-start.gif" width="420" alt="Animación de la alerta de inicio de periodo en el panel">

## 7. Apple Watch y alertas

La app del Watch te permite sumar o restar puntos (− y + para cada equipo), cambiar el periodo e iniciar o pausar el reloj desde tu muñeca. Sigue a tu teléfono, así que ambos muestran siempre el mismo marcador. Un aviso y un toque en tu teléfono y tu reloj indican cuándo empieza un periodo y cuándo termina el partido.

<img src="images/7-watch-es.png" width="200" alt="Control remoto en Apple Watch">

## 8. Prueba el marcador simulado

¿No tienes un marcador a la mano, o quieres ver un partido completo? En la pantalla Buscar marcadores toca **Probar el marcador simulado**. La pantalla del partido funciona igual. Al final, un panel simulado muestra lo mismo que el marcador real: puntos, reloj, periodo, nombres de los equipos (que se desplazan si no caben), tus colores y las alertas de inicio. Debajo hay botones de puntos, periodo e inicio/pausa, y el Apple Watch también lo controla.

Cuando hay un marcador real vinculado, el panel simulado es la vista previa en vivo de ese marcador: el marcador refleja la app y una línea de estado muestra **Marcador sincronizado** cuando el reloj del propio marcador coincide. **Salir del simulador** (tarjeta superior) vuelve a la lista de marcadores.

<img src="images/8-simulator-button-es.png" width="240" alt="El botón Probar el marcador simulado"> <img src="images/8-simulator-es.png" width="240" alt="El marcador simulado al final de la pantalla del partido">

## Solución de problemas

| Problema | Qué probar |
| :--- | :--- |
| El marcador no aparece | Revisa que esté encendido y su LED parpadee en azul, que el Bluetooth esté activado, y desliza la lista hacia abajo para buscar de nuevo. |
| "El firmware del marcador está desactualizado" | Carga el firmware más reciente del repositorio `scoreboard_BT_ESP32S3` (por USB, o por Wi-Fi con la dirección IP). |
| El LED parpadea en cian | Se perdió la conexión. El marcador espera 30 segundos al mismo teléfono y luego se reinicia y vuelve a azul. |
| Los colores, las alertas o los elementos ocultos no hacen nada en el panel | El marcador necesita el firmware más reciente (versión de protocolo 4). La página de colores muestra un aviso cuando es anterior. |
| Cambiar el nombre no hace nada | El marcador necesita el firmware actual; la línea de estado bajo el campo indica el motivo. |
