package com.dart.v2ray.vpn.xray.utils

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.ZipFile

object Utilities {

    fun getUserAssetsPath(context: Context): String {
        val dir = context.filesDir
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir.absolutePath
    }

    fun copyAssets(context: Context) {
        val assets = context.assets
        val files = assets.list("") ?: return
        for (filename in files) {
            if (filename == "geoip.dat" || filename == "geosite.dat") {
                var `in`: InputStream? = null
                var out: OutputStream? = null
                try {
                    `in` = assets.open(filename)
                    val outFile = File(getUserAssetsPath(context), filename)
                    out = FileOutputStream(outFile)
                    copyFile(`in`, out)
                } catch (e: IOException) {
                    e.printStackTrace()
                } finally {
                    if (`in` != null) {
                        try {
                            `in`.close()
                        } catch (e: IOException) {
                            e.printStackTrace()
                        }
                    }
                    if (out != null) {
                        try {
                            out.close()
                        } catch (e: IOException) {
                            e.printStackTrace()
                        }
                    }
                }
            }
        }
    }

    fun resolveNativeExecutable(context: Context, fileName: String): File? {
        val nativeLibraryDir = context.applicationInfo.nativeLibraryDir?.takeIf { it.isNotBlank() }
        if (nativeLibraryDir != null) {
            val inNativeDir = File(nativeLibraryDir, fileName)
            if (inNativeDir.exists()) {
                inNativeDir.setExecutable(true, false)
                return inNativeDir
            }
        }

        return extractNativeExecutableFromApk(context, fileName)
    }

    private fun extractNativeExecutableFromApk(context: Context, fileName: String): File? {
        val sourceApk = context.applicationInfo.sourceDir ?: return null
        val outputDir = File(context.filesDir, "native-bin").apply { mkdirs() }
        val outputFile = File(outputDir, fileName)

        return runCatching {
            ZipFile(sourceApk).use { zip ->
                val entry = Build.SUPPORTED_ABIS
                    .asSequence()
                    .map { abi -> "lib/$abi/$fileName" }
                    .mapNotNull { path -> zip.getEntry(path)?.let { path to it } }
                    .firstOrNull()
                if (entry == null) {
                    Log.w(TAG, "No APK entry found for $fileName in supported ABIs: ${Build.SUPPORTED_ABIS.joinToString(",")}")
                    return@runCatching null
                }

                val zipEntry = entry.second
                val shouldRewrite = !outputFile.exists() ||
                    outputFile.length() <= 0L ||
                    (zipEntry.size > 0 && outputFile.length() != zipEntry.size)

                if (shouldRewrite) {
                    zip.getInputStream(zipEntry).use { input ->
                        FileOutputStream(outputFile, false).use { output ->
                            input.copyTo(output)
                        }
                    }
                }
            }

            outputFile.setExecutable(true, false)
            outputFile
        }.onFailure {
            Log.e(TAG, "Failed to extract $fileName from APK", it)
        }.getOrNull()
    }

    @Throws(IOException::class)
    private fun copyFile(`in`: InputStream, out: OutputStream) {
        val buffer = ByteArray(1024)
        var read: Int
        while (`in`.read(buffer).also { read = it } != -1) {
            out.write(buffer, 0, read)
        }
    }

    private const val TAG = "Utilities"
}

