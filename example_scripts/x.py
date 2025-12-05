import xarray as xr
import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import gcsfs
import numpy as np

# 你的 GCS 路径
gcs_path = "gpm111223/Final_Run/2013/001/3B-HHR.MS.MRG.3IMERG.20130101-S000000-E002959.0000.V07B.HDF5"

print("正在连接 GCS...")
# 初始化 GCS 文件系统
fs = gcsfs.GCSFileSystem(token='google_default')

try:
    # 打开云端文件对象
    fobj = fs.open(gcs_path)

    # 读取数据
    ds = xr.open_dataset(fobj, group='/Grid', engine='h5netcdf')
    
    print("成功读取文件结构。")
    
    # --- 修正点在这里 ---
    # 1. 使用 'precipitation' 而不是 'precipitationCal'
    # 2. transpose('lat', 'lon') 将 (lon, lat) 转为 (lat, lon) 以便绘图
    precip = ds['precipitation'].isel(time=0).transpose('lat', 'lon')

    print("正在绘图...")
    
    plt.figure(figsize=(12, 6))
    ax = plt.axes(projection=ccrs.PlateCarree())
    
    # 添加海岸线
    ax.add_feature(cfeature.COASTLINE)
    ax.add_feature(cfeature.BORDERS, linestyle=':')
    
    # 绘图
    # vmax=10 表示超过 10mm/hr 的都显示为最大颜色，你可以根据需要调整
    precip.plot(ax=ax, 
                transform=ccrs.PlateCarree(), 
                cmap='nipy_spectral', 
                vmin=0.1, vmax=15,
                cbar_kwargs={'label': 'Precipitation (mm/hr)'})
    
    plt.title(f"GPM IMERG Precipitation\n{gcs_path.split('/')[-1]}")
    
    # 保存图片
    save_name = 'gpm_result.png'
    plt.savefig(save_name, bbox_inches='tight', dpi=300)
    print(f"成功！图片已保存为: {save_name}")
    
    # 如果是在 Jupyter 中可以取消注释下面这行
    # plt.show() 
    
except Exception as e:
    print(f"发生错误: {e}")
