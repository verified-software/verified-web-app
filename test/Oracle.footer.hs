
user :: C.User -> M.T_User_2
user C.Alice = M.C_Alice_4
user C.Bob = M.C_Bob_6
backUser :: M.T_User_2 -> C.User
backUser M.C_Alice_4 = C.Alice
backUser M.C_Bob_6 = C.Bob
count :: C.Count -> M.T_Count_10
count C.Zero = M.C_Zero_12
count (C.More n) = M.C_More_14 (count n)
glyph :: C.Glyph -> M.T_Glyph_210
glyph (C.Plain c) = M.C_Plain_212 (toSafe c)
glyph C.Lt = M.C_Lt_214
glyph C.Gt = M.C_Gt_216
glyph C.Amp = M.C_Amp_218
glyph C.DQuote = M.C_DQuote_220
glyph C.SQuote = M.C_SQuote_222
backGlyph :: M.T_Glyph_210 -> C.Glyph
backGlyph (M.C_Plain_212 c) = C.Plain (fromSafe c)
backGlyph M.C_Lt_214 = C.Lt
backGlyph M.C_Gt_216 = C.Gt
backGlyph M.C_Amp_218 = C.Amp
backGlyph M.C_DQuote_220 = C.DQuote
backGlyph M.C_SQuote_222 = C.SQuote
session :: C.Session -> M.T_Session_246
session C.Guest = M.C_Guest_248
session (C.Logged u) = M.C_Logged_250 (user u)
backSession :: M.T_Session_246 -> C.Session
backSession M.C_Guest_248 = C.Guest
backSession (M.C_Logged_250 u) = C.Logged (backUser u)
post :: C.Post -> M.T_Post_252
post (C.PostC u text) = M.C_PostC_254 (user u) (map glyph text)
backPost :: M.T_Post_252 -> C.Post
backPost (M.C_PostC_254 u text) = C.PostC (backUser u) (map backGlyph text)
request :: C.Request -> M.T_Request_276
request C.ReadPosts = M.C_ReadPosts_278
request (C.Authenticate u) = M.C_Authenticate_280 (user u)
request (C.CreatePost text) = M.C_CreatePost_282 (map glyph text)
request (C.EditPost i text) = M.C_EditPost_284 (count i) (map glyph text)
request C.Logout = M.C_Logout_286
backError :: M.T_Error_288 -> C.Error
backError M.C_Unauthorized_290 = C.Unauthorized
backError M.C_BadTransition_292 = C.BadTransition
backError M.C_TooLong_294 = C.TooLong
backError M.C_ForumFull_296 = C.ForumFull
backError M.C_EditDenied_298 = C.EditDenied
backResult :: M.T_Result_300 -> C.Result
backResult (M.C_Denied_302 e) = C.Denied (backError e)
backResult (M.C_Accepted_304 s ps) = C.Accepted (backSession s) (map backPost ps)
execute :: C.Count -> C.Count -> C.Session -> C.Request -> [C.Post] -> C.Result
execute tl pl s r ps = backResult (M.d_execute_342 (count tl) (count pl) (session s) (request r) (map post ps))
render :: [C.Glyph] -> [C.Glyph]
render = map backGlyph . M.d_render_240 . map glyph
