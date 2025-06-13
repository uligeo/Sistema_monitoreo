library(shiny)
library(ggplot2)
library(dplyr)
library(plotly)
library(lubridate)
library(bslib)
library(stringr)  # Para extraer fechas de nombres de archivo
library(shinyjs)

# Definir los sitios disponibles
sitios <- c("muxupi_poligono", "hopelchen", "chinquila_poligono")

# Función para cargar datos de series temporales
cargar_serie_temporal <- function(sitio) {
  ruta_archivo <- file.path("timeseries", sitio, paste0(sitio, "_ndvi_timeseries.csv"))
  datos <- read.csv(ruta_archivo, stringsAsFactors = FALSE)
  datos$date <- as.Date(datos$date)
  return(datos)
}

# Función para obtener lista de imágenes disponibles
obtener_imagenes <- function(sitio) {
  ruta_imagenes <- file.path("Imagenes", sitio)
  archivos <- list.files(ruta_imagenes, pattern = "*.png")
  return(archivos)
}

# UI de la aplicación
ui <- fluidPage(
  # Habilitar shinyjs
  shinyjs::useShinyjs(),

  theme = bs_theme(
    bg = "#FFFFFF",
    fg = "#333333", 
    primary = "#3498DB",
    base_font = font_google("Roboto"),
    heading_font = font_google("Roboto Condensed"),
    version = 5,
    bootswatch = "minty"
  ),

  # Estilos CSS personalizados para controlar tamaño de imágenes
  tags$head(
    tags$style(HTML("
      /* Miniaturas: asegurar que las imágenes no se desborden */
      #img_container_rgb img,
      #img_container_ndvi img,
      #img_container_falsecolor img {
        width: 100% !important;
        max-height: 400px !important;
        height: auto !important;
        object-fit: contain;
        border-radius: 4px;
      }

      /* Imagen ampliada en modal */
      #modal_imagen .modal-dialog {
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
        width: 100vw !important;
        height: 100vh !important;
        max-width: 100vw !important;
        max-height: 100vh !important;
        margin: 0 !important;
        padding: 0 !important;
      }
      #modal_imagen .modal-content {
        background: #222c !important; /* Fondo oscuro translúcido */
        border-radius: 0 !important;
        border: none !important;
        box-shadow: none !important;
        display: flex !important;
        flex-direction: column !important;
        align-items: center !important;
        justify-content: flex-start !important;
        position: relative !important;
        width: 100vw !important;
        max-width: 100vw !important;
        height: 100vh !important;
        max-height: 100vh !important;
        padding: 0 !important;
        z-index: 2000 !important;
        overflow-y: auto !important;
      }
      #modal_imagen .modal-body {
        padding: 0 !important;
        margin: 0 !important;
        background: transparent !important;
        width: 100vw !important;
        min-height: 100vh !important;
        max-width: 100vw !important;
        max-height: none !important;
        overflow: visible !important;
        display: flex !important;
        flex-direction: column !important;
        align-items: center !important;
        justify-content: flex-start !important;
        position: relative !important;
        flex: 1 1 auto !important;
      }
      #modal_imagen .modal-body img {
        width: auto !important;
        height: auto !important;
        max-width: 95vw !important;
        max-height: none !important;
        object-fit: contain !important;
        display: block !important;
        margin: 0 auto !important;
        box-shadow: 0 2px 12px rgba(0,0,0,0.15);
        border-radius: 8px;
        position: relative !important;
        z-index: 1 !important;
      }
      #modal_imagen .modal-footer {
        width: 100vw !important;
        text-align: center !important;
        padding: 0 !important;
        background: transparent !important;
        border: none !important;
        margin: 0 !important;
        position: fixed !important;
        left: 0 !important;
        bottom: 0 !important;
        z-index: 3000 !important;
      }

      /* Estilos para la cuadrícula */
      .grid-overlay {
        position: absolute !important;
        top: 0 !important;
        left: 0 !important;
        pointer-events: none !important;
        z-index: 2 !important;
        background: transparent !important;
      }

      .grid-line {
        position: absolute !important;
        background-color: rgba(255, 255, 255, 0.5) !important;
        z-index: 1051 !important;
      }

      .grid-number {
        position: absolute !important;
        color: white !important;
        background-color: rgba(0, 0, 0, 0.6) !important;
        padding: 2px 6px !important;
        border-radius: 3px !important;
        font-size: 12px !important;
        font-weight: bold !important;
        z-index: 1052 !important;
      }

      .modal-backdrop.show {
        opacity: 1 !important;
        background-color: #fff !important;
      }
    ")),
    tags$script(HTML("
      function createGrid() {
        const modalBody = document.querySelector('#modal_imagen .modal-body');
        const img = modalBody.querySelector('img');
        if (!img) return;
        
        // Eliminar cuadrícula anterior si existe
        const oldGrid = modalBody.querySelector('.grid-overlay');
        if (oldGrid) oldGrid.remove();
        
        // Crear overlay
        const gridOverlay = document.createElement('div');
        gridOverlay.className = 'grid-overlay';
        
        // El overlay debe tener el mismo tamaño que la imagen
        gridOverlay.style.width = img.width + 'px';
        gridOverlay.style.height = img.height + 'px';
        gridOverlay.style.left = img.offsetLeft + 'px';
        gridOverlay.style.top = img.offsetTop + 'px';
        
        // Crear cuadrícula de 10x10
        const gridSize = 10;
        const cellWidth = img.width / gridSize;
        const cellHeight = img.height / gridSize;
        
        // Líneas verticales
        for (let i = 1; i < gridSize; i++) {
          const line = document.createElement('div');
          line.className = 'grid-line';
          line.style.width = '1px';
          line.style.height = img.height + 'px';
          line.style.left = (i * cellWidth) + 'px';
          line.style.top = '0px';
          line.style.position = 'absolute';
          gridOverlay.appendChild(line);
        }
        
        // Líneas horizontales
        for (let i = 1; i < gridSize; i++) {
          const line = document.createElement('div');
          line.className = 'grid-line';
          line.style.height = '1px';
          line.style.width = img.width + 'px';
          line.style.top = (i * cellHeight) + 'px';
          line.style.left = '0px';
          line.style.position = 'absolute';
          gridOverlay.appendChild(line);
        }
        
        // Números
        let number = 1;
        for (let row = 0; row < gridSize; row++) {
          for (let col = 0; col < gridSize; col++) {
            const numberDiv = document.createElement('div');
            numberDiv.className = 'grid-number';
            numberDiv.textContent = number;
            numberDiv.style.left = (col * cellWidth + 5) + 'px';
            numberDiv.style.top = (row * cellHeight + 5) + 'px';
            numberDiv.style.position = 'absolute';
            gridOverlay.appendChild(numberDiv);
            number++;
          }
        }
        
        modalBody.appendChild(gridOverlay);
      }
      
      // Observar cambios en el modal
      const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
          if (mutation.addedNodes.length) {
            const modal = document.querySelector('#modal_imagen');
            if (modal && modal.classList.contains('show')) {
              const img = modal.querySelector('img');
              if (img) {
                img.onload = createGrid;
                if (img.complete) createGrid();
              }
            }
          }
        });
      });
      
      observer.observe(document.body, {
        childList: true,
        subtree: true
      });
      
      // Actualizar cuadrícula cuando se redimensiona la ventana
      window.addEventListener('resize', function() {
        const modal = document.querySelector('#modal_imagen');
        if (modal && modal.classList.contains('show')) {
          createGrid();
        }
      });
    "))
  ),

  # Título con estilo minimalista
  tags$div(
    style = "padding: 20px 0; text-align: center; border-bottom: 1px solid #eee; margin-bottom: 20px;",
    tags$h2("Sistema de monitoreo con satelites", 
            style = "color: #3498DB; font-weight: 300;")
  ),
  
  # Controles en fila superior
  fluidRow(
    column(3,
           selectInput("sitio", "Sitio:", choices = sitios, width = "100%"),
           style = "padding-right: 5px;"
    ),
    column(2,
           div(style = "margin-top: 25px;", 
               downloadButton("descargar_datos", "Descargar CSV", 
                           style = "width: 100%; background-color: #3498DB;"))
    ),
    column(2,
           div(style = "margin-top: 25px; text-align: right;",
               actionButton("ayuda", "Ayuda", icon = icon("question-circle"),
                         style = "background-color: #f8f9fa; color: #3498DB; border-color: #3498DB;"))
    )
  ),
  
  # Espacio adicional
  tags$div(style = "margin: 10px 0;"),
  
  # Gráfico de serie temporal
  fluidRow(
    column(12,
           tags$div(
             style = "background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin-bottom: 20px;",
             tags$h4("Serie Temporal NDVI", style = "color: #3498DB; margin-bottom: 15px; font-weight: 300;"),
             plotlyOutput("grafico_serie_temporal", height = "450px")
           )
    )
  ),
  
  # Imágenes en fila
  fluidRow(
    column(12,
           tags$div(
             style = "background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin-bottom: 20px;",
             tags$h4("Imágenes del Sitio", style = "color: #3498DB; margin-bottom: 15px; font-weight: 300;"),
             fluidRow(
               column(4,
                     div(style = "text-align: center; background-color: white; padding: 10px; border-radius: 5px;",
                         h5("RGB", style = "color: #3498DB; font-weight: 300;"), 
                         div(id = "img_container_rgb",
                             imageOutput("imagen_rgb_thumbnail"),
                             actionButton("ver_rgb", "Ampliar", 
                                       class = "btn-sm btn-primary", 
                                       style = "margin-top: 10px; width: 100%;")
                         )
                     )
               ),
               column(4,
                     div(style = "text-align: center; background-color: white; padding: 10px; border-radius: 5px;",
                         h5("NDVI", style = "color: #3498DB; font-weight: 300;"), 
                         div(id = "img_container_ndvi",
                             imageOutput("imagen_ndvi_thumbnail"),
                             actionButton("ver_ndvi", "Ampliar", 
                                       class = "btn-sm btn-primary", 
                                       style = "margin-top: 10px; width: 100%;")
                         )
                     )
               ),
               column(4,
                     div(style = "text-align: center; background-color: white; padding: 10px; border-radius: 5px;",
                         h5("Falso Color", style = "color: #3498DB; font-weight: 300;"), 
                         div(id = "img_container_falsecolor",
                             imageOutput("imagen_falsecolor_thumbnail"),
                             actionButton("ver_falsecolor", "Ampliar", 
                                       class = "btn-sm btn-primary", 
                                       style = "margin-top: 10px; width: 100%;")
                         )
                     )
               )
             ),
             tags$div(
               style = "background-color: #fff; padding: 10px; border-radius: 5px; margin-top: 20px; text-align: center;",
               h5("NDVI Promedio Mes Anterior", style = "color: #3498DB; font-weight: 300;"),
               imageOutput("imagen_ndvi_mes_anterior", height = "300px"),
               actionButton("ver_ndvi_mes_anterior", "Ampliar", class = "btn-sm btn-primary", style = "margin-top: 10px; width: 100%;")
             ),
             tags$div(
               style = "background-color: #fff; padding: 10px; border-radius: 5px; margin-top: 20px; text-align: center;",
               h5("NDVI Diferencia Mes", style = "color: #3498DB; font-weight: 300;"),
               imageOutput("imagen_ndvi_diferencia", height = "300px"),
               actionButton("ver_ndvi_diferencia", "Ampliar", class = "btn-sm btn-primary", style = "margin-top: 10px; width: 100%;")
             )
           )
    )
  ),
  
  # Información estadística
  fluidRow(
    column(12,
           tags$div(
             style = "background-color: #f8f9fa; padding: 15px; border-radius: 5px;",
             tags$h4("Información Estadística", style = "color: #3498DB; margin-bottom: 15px; font-weight: 300;"),
             verbatimTextOutput("info_punto")
           )
    )
  ),
  
  # Modal para mostrar imagen ampliada
  tags$div(id = "modal_imagen",
           class = "modal fade",
           tags$div(class = "modal-dialog modal-xl",
                    tags$div(class = "modal-content",
                             # Título como overlay
                             tags$div(class = "modal-header",
                                      tags$h4(class = "modal-title", textOutput("modal_titulo"))
                             ),
                             tags$div(class = "modal-body", 
                                      imageOutput("imagen_ampliada")
                             ),
                             tags$div(class = "modal-footer",
                                      actionButton("cerrar_modal_imagen", "Cerrar", class = "btn-sm btn-primary", style = "margin-top: 10px; width: 100%;")
                             )
                    )
           )
  ),
  
  # Pie de página minimalista
  tags$div(
    style = "text-align: center; margin-top: 30px; padding: 20px 0; color: #aaa; border-top: 1px solid #eee; font-size: 12px;",
    "©2025 - Sistema de Monitoreo con satelites - Sentinel-2"
  )
)

# Server de la aplicación
server <- function(input, output, session) {
  
  # Datos reactivos
  datos_sitio <- reactive({
    datos <- cargar_serie_temporal(input$sitio)
    # Filtrar por rango de fechas si está disponible
    if (!is.null(input$rango_fechas)) {
      datos <- datos[datos$date >= input$rango_fechas[1] & datos$date <= input$rango_fechas[2], ]
    }
    return(datos)
  })
  
  # Actualizar selector de fechas de imagen según sitio
  observeEvent(input$sitio, {
    ruta <- file.path("Imagenes", input$sitio)
    archivos <- list.files(ruta, pattern = "*.png")
    fechas <- str_extract(archivos, "\\d{4}-\\d{2}-\\d{2}")
    fechas <- fechas[!is.na(fechas)]
    fechas <- sort(unique(fechas))
    if(length(fechas) == 0) fechas <- "-"
    updateSelectInput(session, "fecha_imagen", choices = fechas, selected = tail(fechas, 1))
  }, ignoreInit = TRUE)
  
  # Encontrar imágenes para cada tipo
  imagenes_disponibles <- reactive({
    sitio <- input$sitio
    imagenes <- obtener_imagenes(sitio)
    
    # Si se especificó fecha, filtrar imágenes de esa fecha
    if(!is.null(input$fecha_imagen) && input$fecha_imagen != "-" && nzchar(input$fecha_imagen)) {
      imagenes <- imagenes[str_detect(imagenes, fixed(input$fecha_imagen))]
    }
    
    # Intentar encontrar imágenes específicas
    rgb_img <- imagenes[grep("RGB_", imagenes)]
    if(length(rgb_img) == 0) rgb_img <- imagenes[grep("_RGB", imagenes)]
    if(length(rgb_img) == 0) rgb_img <- imagenes[grep("rgb", tolower(imagenes))]
    
    ndvi_img <- imagenes[grep("NDVI_[0-9]", imagenes)]
    if(length(ndvi_img) == 0) ndvi_img <- imagenes[grep("ndvi", tolower(imagenes))]
    
    falsecolor_img <- imagenes[grep("FalseColor", imagenes)]
    if(length(falsecolor_img) == 0) falsecolor_img <- imagenes[grep("falsecolor", tolower(imagenes))]
    if(length(falsecolor_img) == 0) falsecolor_img <- imagenes[grep("false", tolower(imagenes))]
    
    # Si no se encuentran imágenes específicas, usar las primeras disponibles
    if(length(rgb_img) == 0 && length(imagenes) > 0) rgb_img <- imagenes[1]
    if(length(ndvi_img) == 0 && length(imagenes) > 1) ndvi_img <- imagenes[2]
    if(length(falsecolor_img) == 0 && length(imagenes) > 2) falsecolor_img <- imagenes[3]
    
    list(
      rgb = if(length(rgb_img) > 0) rgb_img[1] else NULL,
      ndvi = if(length(ndvi_img) > 0) ndvi_img[1] else NULL,
      falsecolor = if(length(falsecolor_img) > 0) falsecolor_img[1] else NULL
    )
  })
  
  # Gráfico interactivo de serie temporal
  output$grafico_serie_temporal <- renderPlotly({
    datos <- datos_sitio()
    
    p <- ggplot(datos, aes(x = date, y = ndvi_mean)) +
      geom_line(color = "#3498DB", size = 1) +
      geom_smooth(method = "lm", se = FALSE, color = "red", linetype = "dashed", size = 1) +
      labs(x = "Fecha", y = "NDVI Promedio") +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "none",
        panel.grid.minor = element_blank(),
        panel.border = element_blank(),
        panel.background = element_rect(fill = "white", color = NA),
        plot.background = element_rect(fill = "white", color = NA)
      )
    
    ggplotly(p) %>% 
      layout(
        margin = list(l = 50, r = 50, b = 100, t = 30),
        hoverlabel = list(
          bgcolor = "white",
          font = list(color = "#333333")
        )
      )
  })
  
  # Mostrar miniaturas de imágenes
  output$imagen_rgb_thumbnail <- renderImage({
    req(imagenes_disponibles()$rgb)
    ruta_imagen <- file.path("Imagenes", input$sitio, imagenes_disponibles()$rgb)
    
    list(src = ruta_imagen,
         contentType = "image/png",
         width = "100%",
         height = "auto",
         alt = "RGB")
  }, deleteFile = FALSE)
  
  output$imagen_ndvi_thumbnail <- renderImage({
    req(imagenes_disponibles()$ndvi)
    ruta_imagen <- file.path("Imagenes", input$sitio, imagenes_disponibles()$ndvi)
    
    list(src = ruta_imagen,
         contentType = "image/png",
         width = "100%",
         height = "auto",
         alt = "NDVI")
  }, deleteFile = FALSE)
  
  output$imagen_falsecolor_thumbnail <- renderImage({
    req(imagenes_disponibles()$falsecolor)
    ruta_imagen <- file.path("Imagenes", input$sitio, imagenes_disponibles()$falsecolor)
    
    list(src = ruta_imagen,
         contentType = "image/png",
         width = "100%",
         height = "auto",
         alt = "Falso Color")
  }, deleteFile = FALSE)
  
  # Mostrar imagen ampliada en el modal
  output$modal_titulo <- renderText({
    req(input$imagen_seleccionada)
    tipo <- input$imagen_seleccionada
    titulos <- list(
      rgb = "Imagen RGB",
      ndvi = "Índice de Vegetación NDVI",
      falsecolor = "Imagen de Falso Color"
    )
    return(titulos[[tipo]])
  })
  
  output$imagen_ampliada <- renderImage({
    req(input$imagen_seleccionada)
    tipo <- input$imagen_seleccionada
    
    imagen_nombre <- imagenes_disponibles()[[tipo]]
    req(imagen_nombre)
    
    ruta_imagen <- file.path("Imagenes", input$sitio, imagen_nombre)
    
    list(src = ruta_imagen,
         contentType = "image/png",
         width = "100%",
         alt = paste("Imagen", tipo))
  }, deleteFile = FALSE)
  
  # Mostrar imagen NDVI promedio mes anterior
  output$imagen_ndvi_mes_anterior <- renderImage({
    sitio <- input$sitio
    # Buscar la imagen más reciente NDVI_promedio_mes_anterior_YYYY-MM.png
    ruta_dir <- file.path("Imagenes", sitio)
    archivos <- list.files(ruta_dir, pattern = "NDVI_promedio_mes_anterior_\\d{4}-\\d{2}\\.png", full.names = TRUE)
    if (length(archivos) == 0) return(NULL)
    # Elegir la más reciente por nombre
    archivo <- archivos[order(archivos, decreasing = TRUE)][1]
    list(src = archivo, contentType = "image/png", width = "auto", height = 300, alt = "NDVI Promedio Mes Anterior")
  }, deleteFile = FALSE)
  
  # Mostrar imagen NDVI diferencia mes
  output$imagen_ndvi_diferencia <- renderImage({
    sitio <- input$sitio
    ruta_dir <- file.path("Imagenes", sitio)
    archivos <- list.files(ruta_dir, pattern = "NDVI_diferencia_\\d{4}-\\d{2}-\\d{2}_vs_\\d{4}-\\d{2}\\.png", full.names = TRUE)
    if (length(archivos) == 0) return(NULL)
    archivo <- archivos[order(archivos, decreasing = TRUE)][1]
    list(src = archivo, contentType = "image/png", width = "auto", height = 300, alt = "NDVI Diferencia Mes")
  }, deleteFile = FALSE)
  
  # Información estadística
  output$info_punto <- renderPrint({
    datos <- datos_sitio()
    
    cat("Sitio:", input$sitio, "\n\n")
    
    cat("Resumen Estadístico de NDVI:\n")
    print(summary(datos$ndvi_mean))
    
    cat("\nResumen Estadístico de Cobertura de Nubes (%):\n")
    print(summary(datos$cloud_cover))
    
    # Información adicional
    cat("\nPeriodo analizado: ", format(min(datos$date), "%d/%m/%Y"), " a ", 
        format(max(datos$date), "%d/%m/%Y"), "\n", sep="")
    
    cat("\nDías totales en la serie: ", nrow(datos), "\n")
    
    # Para el sitio actual
    cat("\nImágenes disponibles para este sitio:\n")
    if(!is.null(imagenes_disponibles()$rgb)) {
      cat("- RGB: ", imagenes_disponibles()$rgb, "\n")
    }
    if(!is.null(imagenes_disponibles()$ndvi)) {
      cat("- NDVI: ", imagenes_disponibles()$ndvi, "\n")
    }
    if(!is.null(imagenes_disponibles()$falsecolor)) {
      cat("- Falso Color: ", imagenes_disponibles()$falsecolor, "\n")
    }
  })
  
  # Mostrar ayuda
  observeEvent(input$ayuda, {
    showModal(modalDialog(
      title = "Ayuda de la Aplicación",
      HTML("<p><strong>Cómo usar esta aplicación:</strong></p>
            <ol>
              <li>Seleccione un sitio en el menú desplegable.</li>
              <li>Ajuste el rango de fechas si lo desea.</li>
              <li>Explore la serie temporal de NDVI interactiva.</li>
              <li>Vea las imágenes disponibles (RGB, NDVI y Falso Color).</li>
              <li>Haga clic en cualquier imagen para verla ampliada.</li>
              <li>Puede descargar los datos de la serie temporal como CSV.</li>
            </ol>"),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cerrar")
      )
    ))
  })
  
  # Descargar datos
  output$descargar_datos <- downloadHandler(
    filename = function() {
      paste(input$sitio, "_datos.csv", sep = "")
    },
    content = function(file) {
      write.csv(datos_sitio(), file, row.names = FALSE)
    }
  )
  
  # Observadores para botones de ampliar imágenes
  observeEvent(input$ver_rgb, {
    output$imagen_ampliada <- renderImage({
      req(imagenes_disponibles()$rgb)
      ruta_imagen <- file.path("Imagenes", input$sitio, imagenes_disponibles()$rgb)
      list(src = ruta_imagen, contentType = "image/png", width = "100%", alt = "Imagen RGB")
    }, deleteFile = FALSE)
    
    output$modal_titulo <- renderText({ "Imagen RGB" })
    
    shinyjs::runjs("$('#modal_imagen').modal('show');")
  })
  
  observeEvent(input$ver_ndvi, {
    output$imagen_ampliada <- renderImage({
      req(imagenes_disponibles()$ndvi)
      ruta_imagen <- file.path("Imagenes", input$sitio, imagenes_disponibles()$ndvi)
      list(src = ruta_imagen, contentType = "image/png", width = "100%", alt = "Imagen NDVI")
    }, deleteFile = FALSE)
    
    output$modal_titulo <- renderText({ "Índice de Vegetación NDVI" })
    
    shinyjs::runjs("$('#modal_imagen').modal('show');")
  })
  
  observeEvent(input$ver_falsecolor, {
    output$imagen_ampliada <- renderImage({
      req(imagenes_disponibles()$falsecolor)
      ruta_imagen <- file.path("Imagenes", input$sitio, imagenes_disponibles()$falsecolor)
      list(src = ruta_imagen, contentType = "image/png", width = "100%", alt = "Imagen Falso Color")
    }, deleteFile = FALSE)
    
    output$modal_titulo <- renderText({ "Imagen de Falso Color" })
    
    shinyjs::runjs("$('#modal_imagen').modal('show');")
  })
  
  # Botón para cerrar el modal de imagen ampliada
  observeEvent(input$cerrar_modal_imagen, {
    shinyjs::runjs("$('#modal_imagen').modal('hide');")
  })
  
  # Botón para ampliar NDVI Promedio Mes Anterior
  observeEvent(input$ver_ndvi_mes_anterior, {
    sitio <- input$sitio
    ruta_dir <- file.path("Imagenes", sitio)
    archivos <- list.files(ruta_dir, pattern = "NDVI_promedio_\\d{4}-\\d{2}\\.png", full.names = TRUE)
    if (length(archivos) == 0) return(NULL)
    archivo <- archivos[order(archivos, decreasing = TRUE)][1]
    output$imagen_ampliada <- renderImage({
      list(src = archivo, contentType = "image/png", width = "100%", alt = "NDVI Promedio Mes Anterior")
    }, deleteFile = FALSE)
    output$modal_titulo <- renderText({ "NDVI Promedio Mes Anterior" })
    shinyjs::runjs("$('#modal_imagen').modal('show');")
  })

  # Botón para ampliar NDVI Diferencia Mes
  observeEvent(input$ver_ndvi_diferencia, {
    sitio <- input$sitio
    ruta_dir <- file.path("Imagenes", sitio)
    archivos <- list.files(ruta_dir, pattern = "NDVI_diferencia_\\d{4}-\\d{2}-\\d{2}_vs_\\d{4}-\\d{2}\\.png", full.names = TRUE)
    if (length(archivos) == 0) return(NULL)
    archivo <- archivos[order(archivos, decreasing = TRUE)][1]
    output$imagen_ampliada <- renderImage({
      list(src = archivo, contentType = "image/png", width = "100%", alt = "NDVI Diferencia Mes")
    }, deleteFile = FALSE)
    output$modal_titulo <- renderText({ "NDVI Diferencia Mes" })
    shinyjs::runjs("$('#modal_imagen').modal('show');")
  })
}

# Ejecutar la aplicación
shinyApp(ui, server) 