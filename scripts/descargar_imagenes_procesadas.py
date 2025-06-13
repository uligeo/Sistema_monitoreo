import ee
import geopandas as gpd
import os
import json
from datetime import datetime, timedelta
import pandas as pd
import numpy as np
from PIL import Image
import io
import requests
import matplotlib.pyplot as plt
import seaborn as sns
import time

# Configuración de autenticación persistente
def initialize_earth_engine():
    """Inicializa Earth Engine con manejo de errores"""
    try:
        credentials_path = os.path.expanduser('~/.config/earthengine/credentials')
        if not os.path.exists(credentials_path):
            os.makedirs(os.path.dirname(credentials_path), exist_ok=True)
            print("🔐 Autenticando Earth Engine...")
            ee.Authenticate()
        ee.Initialize()
        print("✅ Earth Engine inicializado correctamente")
        return True
    except Exception as e:
        print(f"❌ Error inicializando Earth Engine: {str(e)}")
        return False

# Configuración de directorios - MODIFICADO para usar la estructura correcta
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGENES_DIR = os.path.join(BASE_DIR, 'Imagenes')  # Cambio aquí
TIMESERIES_DIR = os.path.join(BASE_DIR, 'timeseries')  # Cambio aquí

def create_directories(polygon_name):
    """Crea los directorios necesarios para un polígono"""
    polygon_images_dir = os.path.join(IMAGENES_DIR, polygon_name)  # Cambio aquí
    polygon_timeseries_dir = os.path.join(TIMESERIES_DIR, polygon_name)
    
    for directory in [polygon_images_dir, polygon_timeseries_dir]:
        if not os.path.exists(directory):
            os.makedirs(directory)
            print(f"✅ Directorio creado: {directory}")
    
    return polygon_images_dir, polygon_timeseries_dir

def get_best_image_in_period(geometry, fecha_inicio, fecha_fin, max_cloud_cover=25):
    """Obtiene la mejor imagen en un período dado"""
    try:
        print(f"🔍 Buscando imágenes entre {fecha_inicio} y {fecha_fin}")
        
        # Crear colección con filtros más flexibles
        collection = (ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')  # Usar colección harmonizada
                     .filterDate(fecha_inicio, fecha_fin)
                     .filterBounds(geometry)
                     .filter(ee.Filter.lt('CLOUDY_PIXEL_PERCENTAGE', max_cloud_cover))
                     .sort('CLOUDY_PIXEL_PERCENTAGE'))  # Ordenar por menor cobertura de nubes
        
        # Verificar si hay imágenes
        size = collection.size().getInfo()
        print(f"📊 Imágenes encontradas con <{max_cloud_cover}% nubes: {size}")
        
        if size == 0:
            # Intentar con mayor tolerancia a nubes
            print(f"⚠️ Reintentando con hasta 50% de nubes...")
            collection = (ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
                         .filterDate(fecha_inicio, fecha_fin)
                         .filterBounds(geometry)
                         .filter(ee.Filter.lt('CLOUDY_PIXEL_PERCENTAGE', 50))
                         .sort('CLOUDY_PIXEL_PERCENTAGE'))
            
            size = collection.size().getInfo()
            print(f"📊 Imágenes encontradas con <50% nubes: {size}")
            
            if size == 0:
                return None, None
        
        # Obtener la imagen con menos nubes
        best_image = ee.Image(collection.first())
        
        # Obtener metadatos de la imagen
        image_date = ee.Date(best_image.get('system:time_start')).format('YYYY-MM-dd').getInfo()
        cloud_cover = best_image.get('CLOUDY_PIXEL_PERCENTAGE').getInfo()
        
        print(f"✅ Mejor imagen encontrada: {image_date} (nubes: {cloud_cover:.1f}%)")
        
        return best_image, image_date
        
    except Exception as e:
        print(f"❌ Error obteniendo imagen: {str(e)}")
        return None, None

def get_monthly_average(geometry, fecha_reciente):
    """Obtiene el promedio mensual de NDVI para el mes anterior a la fecha dada"""
    try:
        # Calcular el mes anterior
        fecha_obj = datetime.strptime(fecha_reciente, '%Y-%m-%d')
        if fecha_obj.month == 1:
            prev_year = fecha_obj.year - 1
            prev_month = 12
        else:
            prev_year = fecha_obj.year
            prev_month = fecha_obj.month - 1
        
        # Calcular fechas de inicio y fin del mes anterior
        start_date = f"{prev_year}-{prev_month:02d}-01"
        if prev_month == 12:
            end_date = f"{prev_year+1}-01-01"
        else:
            end_date = f"{prev_year}-{prev_month+1:02d}-01"
        
        print(f"📊 Calculando promedio mensual para {prev_year}-{prev_month:02d}...")
        
        # Obtener colección de imágenes del mes anterior
        se2_collection = (ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
               .filterDate(start_date, end_date)
               .filterBounds(geometry)
               .filter(ee.Filter.lt('CLOUDY_PIXEL_PERCENTAGE', 50))  # Más tolerante
               .sort('system:time_start'))
        
        # Verificar si la colección está vacía
        size = se2_collection.size().getInfo()
        if size == 0:
            print(f"⚠️ No se encontraron imágenes para {prev_year}-{prev_month:02d}.")
            return None, None

        print(f"📊 {size} imágenes encontradas para el promedio mensual")

        # Calcular NDVI para cada imagen
        def add_ndvi(image):
            ndvi = image.normalizedDifference(['B8', 'B4']).rename('NDVI')
            return image.addBands(ndvi)
        
        ndvi_collection = se2_collection.map(add_ndvi)
        
        # Calcular la mediana de NDVI para el mes
        monthly_ndvi = ndvi_collection.select('NDVI').median()
        
        return monthly_ndvi, f"{prev_year}-{prev_month:02d}"
        
    except Exception as e:
        print(f"❌ Error calculando promedio mensual: {str(e)}")
        return None, None

def download_image_with_retry(url, output_path, max_retries=3):
    """Descarga una imagen con reintentos"""
    for attempt in range(max_retries):
        try:
            print(f"📥 Descargando: {os.path.basename(output_path)} (intento {attempt + 1})")
            
            response = requests.get(url, timeout=60)  # Timeout de 60 segundos
            response.raise_for_status()
            
            # Verificar que la respuesta contiene una imagen
            if len(response.content) < 1000:  # Si es muy pequeña, probablemente es un error
                raise Exception("Respuesta muy pequeña, posible error del servidor")
            
            with open(output_path, 'wb') as f:
                f.write(response.content)
            
            # Verificar que el archivo se guardó correctamente
            if os.path.exists(output_path) and os.path.getsize(output_path) > 1000:
                print(f"✅ {os.path.basename(output_path)} descargada correctamente")
                return True
            else:
                raise Exception("Archivo no guardado correctamente")
                
        except Exception as e:
            print(f"⚠️ Error en intento {attempt + 1}: {str(e)}")
            if attempt < max_retries - 1:
                print("🔄 Reintentando en 5 segundos...")
                time.sleep(5)
            else:
                print(f"❌ Falló la descarga de {os.path.basename(output_path)} después de {max_retries} intentos")
                return False
    
    return False

def download_processed_images(geometry, fecha_inicio, fecha_fin, output_dir, polygon_name):
    """Descarga imágenes procesadas para un polígono con mejor manejo de errores"""
    try:
        print(f"🖼️ Iniciando descarga de imágenes para {polygon_name}...")
        
        # Obtener la mejor imagen en el período
        image, fecha = get_best_image_in_period(geometry, fecha_inicio, fecha_fin)
        
        if image is None:
            print("❌ No se encontraron imágenes adecuadas")
            return False
        
        # Obtener el promedio mensual del mes anterior
        monthly_avg, fecha_mes_anterior = get_monthly_average(geometry, fecha)
        
        # Crear directorio de salida
        os.makedirs(output_dir, exist_ok=True)
        
        # Obtener los bounds de la geometría para optimizar las descargas
        bounds = geometry.bounds().getInfo()
        print(f"🗺️ Bounds de la geometría: {bounds}")
        
        # Configuración base para descarga
        base_params = {
            'region': geometry,
            'format': 'png',
            'crs': 'EPSG:4326'
        }
        
        # Ajustar dimensiones basado en el tamaño del área
        coords = bounds['coordinates'][0]
        width = abs(coords[2][0] - coords[0][0])  # diferencia en longitud
        height = abs(coords[2][1] - coords[0][1])  # diferencia en latitud
        
        # Calcular dimensiones apropiadas (máximo 2048 para evitar timeouts)
        if max(width, height) > 0.1:  # área grande
            dimensions = 1024
        elif max(width, height) > 0.01:  # área mediana
            dimensions = 2048
        else:  # área pequeña
            dimensions = 4096
        
        print(f"📐 Usando dimensiones: {dimensions}x{dimensions}")
        
        # Lista de imágenes a descargar
        downloads = []
        
        # 1. Imagen RGB (Color natural)
        rgb = image.select(['B4', 'B3', 'B2'])
        # Aplicar corrección de gamma y estiramiento de contraste
        rgb_processed = rgb.divide(10000).pow(0.8).multiply(3.5).clamp(0, 1)
        rgb_clipped = rgb_processed.clip(geometry)
        
        rgb_params = {
            **base_params,
            'dimensions': dimensions,
            'min': 0,
            'max': 1,
            'gamma': 1.0
        }
        
        downloads.append({
            'image': rgb_clipped,
            'params': rgb_params,
            'filename': f'RGB_{fecha}.png',
            'description': 'RGB'
        })
        
        # 2. Imagen NDVI
        ndvi = image.normalizedDifference(['B8', 'B4']).rename('NDVI')
        ndvi_clipped = ndvi.clip(geometry)
        
        ndvi_params = {
            **base_params,
            'dimensions': min(dimensions, 2048),  # NDVI no necesita tanta resolución
            'min': -1,
            'max': 1,
            'palette': ['#d73027', '#f46d43', '#fdae61', '#fee08b', '#ffffbf', '#d9ef8b', '#a6d96a', '#66bd63', '#1a9850']
        }
        
        downloads.append({
            'image': ndvi_clipped,
            'params': ndvi_params,
            'filename': f'NDVI_{fecha}.png',
            'description': 'NDVI'
        })
        
        # 3. Imagen Falso Color (NIR-R-G)
        false_color = image.select(['B8', 'B4', 'B3'])
        false_color_processed = false_color.divide(10000).pow(0.8).multiply(3.5).clamp(0, 1)
        false_color_clipped = false_color_processed.clip(geometry)
        
        false_color_params = {
            **base_params,
            'dimensions': dimensions,
            'min': 0,
            'max': 1,
            'gamma': 1.0
        }
        
        downloads.append({
            'image': false_color_clipped,
            'params': false_color_params,
            'filename': f'FalseColor_{fecha}.png',
            'description': 'Falso Color'
        })
        
        # 4. Promedio mensual NDVI (si está disponible)
        if monthly_avg is not None and fecha_mes_anterior:
            monthly_avg_clipped = monthly_avg.clip(geometry)
            
            monthly_params = {
                **base_params,
                'dimensions': min(dimensions, 2048),
                'min': -1,
                'max': 1,
                'palette': ['#d73027', '#f46d43', '#fdae61', '#fee08b', '#ffffbf', '#d9ef8b', '#a6d96a', '#66bd63', '#1a9850']
            }
            
            downloads.append({
                'image': monthly_avg_clipped,
                'params': monthly_params,
                'filename': f'NDVI_promedio_{fecha_mes_anterior}.png',
                'description': f'NDVI Promedio {fecha_mes_anterior}'
            })
            
            # 5. Imagen de diferencias
            current_ndvi = image.normalizedDifference(['B8', 'B4']).rename('NDVI')
            diff = current_ndvi.subtract(monthly_avg).rename('NDVI_diff')
            diff_clipped = diff.clip(geometry)
            
            diff_params = {
                **base_params,
                'dimensions': min(dimensions, 2048),
                'min': -0.5,
                'max': 0.5,
                'palette': ['#d73027', '#f46d43', '#fdae61', '#ffffbf', '#fee08b', '#d9ef8b', '#a6d96a', '#66bd63', '#1a9850']
            }
            
            downloads.append({
                'image': diff_clipped,
                'params': diff_params,
                'filename': f'NDVI_Diff_{fecha}.png',
                'description': 'Diferencias NDVI'
            })
        
        # Ejecutar descargas
        successful_downloads = 0
        for download in downloads:
            try:
                print(f"🔗 Generando URL para {download['description']}...")
                url = download['image'].getThumbUrl(download['params'])
                
                output_path = os.path.join(output_dir, download['filename'])
                
                if download_image_with_retry(url, output_path):
                    successful_downloads += 1
                
                # Pausa entre descargas para evitar sobrecarga del servidor
                time.sleep(2)
                
            except Exception as e:
                print(f"❌ Error generando/descargando {download['description']}: {str(e)}")
        
        print(f"✅ Descarga completada: {successful_downloads}/{len(downloads)} imágenes exitosas")
        return successful_downloads > 0
        
    except Exception as e:
        print(f"❌ Error en download_processed_images: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return False

def get_ndvi_timeseries(geometry, fecha_inicio, fecha_fin):
    """Obtiene la serie temporal de NDVI para un polígono con mejor manejo de errores"""
    try:
        print(f"📊 Obteniendo serie temporal NDVI de {fecha_inicio} a {fecha_fin}")
        
        # Obtener colección de imágenes
        se2_collection = (ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
               .filterDate(fecha_inicio, fecha_fin)
               .filterBounds(geometry)
               .filter(ee.Filter.lt('CLOUDY_PIXEL_PERCENTAGE', 25))  # Más tolerante para serie temporal
               .sort('system:time_start'))
        
        # Verificar si hay imágenes
        size = se2_collection.size().getInfo()
        print(f"📊 Total de imágenes encontradas: {size}")
        
        if size == 0:
            print("⚠️ No se encontraron imágenes para la serie temporal")
            return pd.DataFrame()
        
        # Calcular NDVI para cada imagen
        def add_ndvi(image):
            ndvi = image.normalizedDifference(['B8', 'B4']).rename('NDVI')
            return image.addBands(ndvi)
        
        ndvi_collection = se2_collection.map(add_ndvi)
        
        # Obtener estadísticas de NDVI para cada imagen
        def get_stats(image):
            stats = image.select('NDVI').reduceRegion(
                reducer=ee.Reducer.mean(),
                geometry=geometry,
                scale=20,  # Escala más gruesa para acelerar
                maxPixels=1e8
            )
            return ee.Feature(None, {
                'date': image.date().format('YYYY-MM-dd'),
                'ndvi_mean': stats.get('NDVI'),
                'cloud_cover': image.get('CLOUDY_PIXEL_PERCENTAGE'),
                'scene_id': image.get('PRODUCT_ID')
            })
        
        # Convertir a lista de características (limitar a 100 imágenes para evitar timeouts)
        limited_collection = ndvi_collection.limit(100)
        print("🔄 Calculando estadísticas NDVI...")
        features = limited_collection.map(get_stats).getInfo()['features']
        
        # Convertir a DataFrame
        data = []
        for feature in features:
            props = feature['properties']
            if props['ndvi_mean'] is not None:  # Solo incluir valores válidos
                data.append({
                    'date': props['date'],
                    'ndvi_mean': props['ndvi_mean'],
                    'cloud_cover': props['cloud_cover'],
                    'scene_id': props.get('scene_id', 'unknown')
                })
        
        if not data:
            print("⚠️ No se obtuvieron datos válidos de NDVI")
            return pd.DataFrame()
        
        df = pd.DataFrame(data)
        df['date'] = pd.to_datetime(df['date'])
        
        # Filtrar valores extremos de NDVI
        df = df[(df['ndvi_mean'] >= -1) & (df['ndvi_mean'] <= 1)]
        
        # Agrupar por fecha y calcular promedios (en caso de múltiples imágenes por día)
        df = df.groupby('date').agg({
            'ndvi_mean': 'mean',
            'cloud_cover': 'mean'
        }).reset_index()
        
        df = df.sort_values('date')
        
        print(f"✅ Serie temporal obtenida: {len(df)} puntos de datos")
        
        return df
        
    except Exception as e:
        print(f"❌ Error obteniendo serie temporal: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return pd.DataFrame()

def procesar_poligono(ruta_geojson, fecha_inicio, fecha_fin):
    """Procesa un polígono y descarga sus imágenes con mejor manejo de errores"""
    try:
        # Leer el archivo GeoJSON
        print(f"📂 Leyendo archivo GeoJSON: {ruta_geojson}")
        
        if not os.path.exists(ruta_geojson):
            print(f"❌ Archivo no encontrado: {ruta_geojson}")
            return None
            
        with open(ruta_geojson, 'r', encoding='utf-8') as f:
            geojson_data = json.load(f)
        
        # Obtener el nombre del polígono del nombre del archivo
        polygon_name = os.path.splitext(os.path.basename(ruta_geojson))[0]
        print(f"📍 Polígono cargado: {polygon_name}")
        
        # Validar estructura del GeoJSON
        if 'features' not in geojson_data or len(geojson_data['features']) == 0:
            print(f"❌ GeoJSON inválido o sin features: {ruta_geojson}")
            return None
        
        # Convertir a geometría de Earth Engine
        feature = geojson_data['features'][0]
        if feature['geometry']['type'] == 'Polygon':
            coords = feature['geometry']['coordinates']
        elif feature['geometry']['type'] == 'MultiPolygon':
            coords = feature['geometry']['coordinates'][0]  # Tomar el primer polígono
        else:
            print(f"❌ Tipo de geometría no soportado: {feature['geometry']['type']}")
            return None
            
        geometry = ee.Geometry.Polygon(coords)
        print("🔄 Geometría convertida a formato Earth Engine")
        
        # Crear directorios necesarios - MODIFICADO para usar estructura correcta
        polygon_images_dir, polygon_timeseries_dir = create_directories(polygon_name)
        print(f"📁 Directorios creados para {polygon_name}")
        
        # Obtener serie temporal
        print(f"⏳ Obteniendo serie temporal para {polygon_name}...")
        df = get_ndvi_timeseries(geometry, fecha_inicio, fecha_fin)

        if df.empty:
            print(f"ℹ️ No se encontraron imágenes válidas para {polygon_name}.")
            return {
                'polygon_name': polygon_name,
                'status': 'no_images_found'
            }

        print(f"📊 Serie temporal obtenida con {len(df)} registros")
        
        # Guardar serie temporal en CSV
        csv_file = os.path.join(polygon_timeseries_dir, f"{polygon_name}_ndvi_timeseries.csv")
        df.to_csv(csv_file, index=False)
        print(f"✅ Serie temporal guardada en: {csv_file}")
        
        # Generar gráfico de serie temporal
        print("📈 Generando gráfico de serie temporal...")
        plt.figure(figsize=(15, 8))
        
        # Subplot para NDVI
        plt.subplot(2, 1, 1)
        plt.plot(df['date'], df['ndvi_mean'], 'g-', linewidth=2, label='NDVI')
        plt.title(f'Serie Temporal NDVI - {polygon_name}', fontsize=14)
        plt.ylabel('NDVI', fontsize=12)
        plt.grid(True, alpha=0.3)
        plt.legend()
        
        # Subplot para cobertura de nubes
        plt.subplot(2, 1, 2)
        plt.plot(df['date'], df['cloud_cover'], 'r-', linewidth=1, alpha=0.7, label='Cobertura de nubes')
        plt.title('Cobertura de Nubes', fontsize=14)
        plt.xlabel('Fecha', fontsize=12)
        plt.ylabel('Porcentaje (%)', fontsize=12)
        plt.grid(True, alpha=0.3)
        plt.legend()
        
        plt.tight_layout()
        
        # Guardar gráfico
        plot_file = os.path.join(polygon_timeseries_dir, f"{polygon_name}_timeseries.png")
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        print(f"✅ Gráfico de serie temporal guardado en: {plot_file}")
        
        # Descargar imágenes procesadas usando un rango de fechas reciente
        fecha_fin_descarga = datetime.now().strftime('%Y-%m-%d')
        fecha_inicio_descarga = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
        
        print(f"🖼️ Descargando imágenes procesadas (últimos 30 días)...")
        
        # CAMBIO: Usar el directorio de imágenes en lugar del directorio processed
        success = download_processed_images(
            geometry,
            fecha_inicio_descarga,
            fecha_fin_descarga,
            polygon_images_dir,  # Cambio aquí
            polygon_name
        )
        
        if success:
            print(f"✅ Procesamiento completado para {polygon_name}")
        else:
            print(f"⚠️ Procesamiento completado para {polygon_name} pero con errores en las descargas")
        
        return {
            'polygon_name': polygon_name,
            'timeseries_csv': csv_file,
            'timeseries_plot': plot_file,
            'images_dir': polygon_images_dir,  # Cambio aquí
            'download_success': success
        }
        
    except Exception as e:
        print(f"❌ Error procesando {ruta_geojson}: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return None

def main():
    """Función principal con mejor manejo de errores"""
    print("🚀 Iniciando proceso de descarga de imágenes satelitales...")
    
    # Inicializar Earth Engine
    if not initialize_earth_engine():
        print("❌ No se pudo inicializar Earth Engine. Abortando.")
        return
    
    # Configurar fechas (último año hasta hoy)
    fecha_fin = datetime.now().strftime('%Y-%m-%d')
    fecha_inicio = (datetime.now() - timedelta(days=365)).strftime('%Y-%m-%d')
    print(f"📅 Rango de fechas: {fecha_inicio} a {fecha_fin}")
    
    # Procesar cada polígono en el directorio Bases/capas_geojson
    bases_dir = os.path.join(BASE_DIR, 'Bases', 'capas_geojson')
    
    if not os.path.exists(bases_dir):
        print(f"❌ Directorio no encontrado: {bases_dir}")
        print("🔧 Creando estructura de directorios de ejemplo...")
        os.makedirs(bases_dir, exist_ok=True)
        print(f"📁 Directorio creado: {bases_dir}")
        print("ℹ️ Coloca tus archivos GeoJSON en este directorio y ejecuta el script nuevamente.")
        return
    
    print(f"📂 Buscando polígonos en: {bases_dir}")
    
    try:
        archivos_encontrados = [f for f in os.listdir(bases_dir) if f.endswith('.geojson')]
    except Exception as e:
        print(f"❌ Error listando archivos en {bases_dir}: {str(e)}")
        return
        
    print(f"📋 Archivos GeoJSON encontrados: {len(archivos_encontrados)}")
    
    if len(archivos_encontrados) == 0:
        print("ℹ️ No se encontraron archivos GeoJSON para procesar.")
        return
    
    resultados_exitosos = 0
    
    for i, file in enumerate(archivos_encontrados, 1):
        ruta_geojson = os.path.join(bases_dir, file)
        print(f"\n{'='*60}")
        print(f"📁 Procesando polígono {i}/{len(archivos_encontrados)}: {file}")
        print(f"{'='*60}")
        
        try:
            resultados = procesar_poligono(ruta_geojson, fecha_inicio, fecha_fin)
            if resultados:
                if resultados.get('status') == 'no_images_found':
                    print(f"🟡 No se encontraron imágenes para procesar en {resultados['polygon_name']}.")
                else:
                    if resultados.get('download_success', False):
                        resultados_exitosos += 1
                        print(f"✅ Procesamiento completado exitosamente para {resultados['polygon_name']}")
                    else:
                        print(f"⚠️ Procesamiento completado con errores para {resultados['polygon_name']}")
            else:
                print(f"❌ El procesamiento de {file} falló completamente.")
                
        except Exception as e:
            print(f"❌ Error crítico procesando {file}: {str(e)}")
            import traceback
            print(traceback.format_exc())
        
        # Pausa entre procesamiento de polígonos
        if i < len(archivos_encontrados):
            print("⏸️ Pausa de 5 segundos antes del siguiente polígono...")
            time.sleep(5)
    
    print(f"\n{'='*60}")
    print(f"🎯 RESUMEN FINAL:")
    print(f"📊 Polígonos procesados exitosamente: {resultados_exitosos}/{len(archivos_encontrados)}")
    print(f"✅ Proceso completado")
    print(f"{'='*60}")

if __name__ == "__main__":
    main()