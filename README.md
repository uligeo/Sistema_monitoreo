# Sistema de Monitoreo Satelital con Sentinel-2

## Descripción
Esta aplicación Shiny proporciona una interfaz interactiva para el monitoreo y análisis de datos satelitales utilizando imágenes de Sentinel-2. Permite visualizar y analizar series temporales de NDVI (Índice de Vegetación de Diferencia Normalizada) para diferentes sitios de interés.

## Características Principales
- Visualización de series temporales de NDVI
- Visualización de imágenes RGB, NDVI y Falso Color
- Análisis de diferencias mensuales en NDVI
- Estadísticas descriptivas de los datos
- Interfaz interactiva y responsiva
- Exportación de datos en formato CSV

## Requisitos del Sistema
- R versión 4.3.2 o superior
- Paquetes de R:
  - shiny (1.8.0)
  - ggplot2 (3.5.0)
  - dplyr (1.1.4)
  - plotly (4.10.3)
  - lubridate (1.9.3)
  - bslib (0.7.0)
  - stringr (1.5.1)
  - shinyjs (2.1.0)

## Estructura del Proyecto
```
.
├── app.R                 # Archivo principal de la aplicación
├── manifest.json         # Archivo de dependencias para Posit Connect
├── Imagenes/            # Directorio de imágenes satelitales
│   ├── muxupi_poligono/
│   ├── hopelchen/
│   └── chinquila_poligono/
└── timeseries/          # Directorio de series temporales
    ├── muxupi_poligono/
    ├── hopelchen/
    └── chinquila_poligono/
```

## Instalación

1. Clonar el repositorio:
```bash
git clone [URL_DEL_REPOSITORIO]
```

2. Instalar las dependencias de R:
```R
install.packages(c("shiny", "ggplot2", "dplyr", "plotly", "lubridate", "bslib", "stringr", "shinyjs"))
```

3. Ejecutar la aplicación:
```R
shiny::runApp()
```

## Uso de la Aplicación

1. **Selección de Sitio**
   - Utilice el menú desplegable para seleccionar el sitio de interés
   - Los sitios disponibles son: muxupi_poligono, hopelchen, chinquila_poligono

2. **Visualización de Datos**
   - La serie temporal de NDVI se muestra en el gráfico interactivo
   - Las imágenes satelitales se pueden visualizar en tres formatos: RGB, NDVI y Falso Color
   - Haga clic en cualquier imagen para verla en tamaño completo

3. **Análisis de Datos**
   - Consulte las estadísticas descriptivas en la sección "Información Estadística"
   - Descargue los datos en formato CSV usando el botón "Descargar CSV"

## Despliegue en Posit Connect

Para desplegar la aplicación en Posit Connect:

1. Asegúrese de tener el archivo `manifest.json` en el directorio raíz
2. Siga las instrucciones de despliegue de Posit Connect
3. La aplicación se desplegará automáticamente con todas las dependencias necesarias

## Contribución
Las contribuciones son bienvenidas. Por favor, siga estos pasos:

1. Fork el repositorio
2. Cree una rama para su característica (`git checkout -b feature/AmazingFeature`)
3. Commit sus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abra un Pull Request

## Licencia
Este proyecto está bajo la Licencia MIT. Vea el archivo `LICENSE` para más detalles.

## Contacto
Para preguntas o soporte, por favor contacte a [SU_CORREO@ejemplo.com]

## Agradecimientos
- Datos satelitales proporcionados por Sentinel-2
- Desarrollado con R y Shiny
- Desplegado en Posit Connect 