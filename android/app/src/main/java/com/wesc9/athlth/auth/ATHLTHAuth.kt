package com.wesc9.athlth.auth

import com.wesc9.athlth.BuildConfig
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.createSupabaseClient

/**
 * Shared Supabase *project*, not shared iOS local storage or Apple Health data.
 * Publishable client keys are public; RLS enforces per-user database access.
 */
object ATHLTHAuth {
    private val client by lazy {
        createSupabaseClient(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_PUBLISHABLE_KEY) {
            install(Auth)
        }
    }

    val sessionStatus get() = client.auth.sessionStatus

    fun signedInEmail(): String? = client.auth.currentUserOrNull()?.email

    suspend fun signIn(email: String, password: String) {
        require(email.isNotBlank() && password.isNotBlank())
        client.auth.signInWith(Email) {
            this.email = email.trim()
            this.password = password
        }
    }

    suspend fun signOut() {
        client.auth.signOut()
    }
}
