package com.wesc9.athlth.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** Uses the exact same JPG blob as its approved iOS .xcassets image. */
@Composable
fun PremiumHero(assetName: String, title: String) {
    val context = LocalContext.current
    val bitmap = remember(assetName) {
        runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.assets.open(assetName).use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (bounds.outWidth / sample > 1500 || bounds.outHeight / sample > 1100) {
                sample *= 2
            }
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            context.assets.open(assetName).use { BitmapFactory.decodeStream(it, null, opts) }
        }.getOrNull()
    }
    if (bitmap != null) {
        Box(
            modifier = Modifier.fillMaxWidth().height(172.dp)
                .clip(RoundedCornerShape(22.dp))
        ) {
            Image(bitmap.asImageBitmap(), contentDescription = title,
                modifier = Modifier.fillMaxWidth().height(172.dp),
                contentScale = ContentScale.Crop)
            Text(title,
                modifier = Modifier.align(Alignment.BottomStart)
                    .graphicsLayer { shadowElevation = 8.dp.toPx() },
                color = Color.White, fontWeight = FontWeight.Bold)
        }
    }
}
