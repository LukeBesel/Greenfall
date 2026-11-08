# [ui2] Machine-draft translations for the simpler workbench strings: fills empty msgstr entries
# in locale/*.po (singular entries; plural entries given as a list). Run from the repo root.
import re, sys

T = {
"{ui_cancel}  back": ["{ui_cancel}  zurück", "{ui_cancel}  volver", "{ui_cancel}  retour", "{ui_cancel}  戻る", "{ui_cancel}  voltar", "{ui_cancel}  返回"],
"%d / %d curiosities": ["%d / %d Kuriositäten", "%d / %d curiosidades", "%d / %d curiosités", "珍品 %d / %d", "%d / %d curiosidades", "奇物 %d / %d"],
"%d / %d collectibles": ["%d / %d Sammelstücke", "%d / %d coleccionables", "%d / %d objets de collection", "コレクション %d / %d", "%d / %d colecionáveis", "收藏品 %d / %d"],
"%d / %d achievements": ["%d / %d Erfolge", "%d / %d logros", "%d / %d succès", "実績 %d / %d", "%d / %d conquistas", "成就 %d / %d"],
"%d / %d entries": ["%d / %d Einträge", "%d / %d entradas", "%d / %d entrées", "項目 %d / %d", "%d / %d entradas", "条目 %d / %d"],
"Build the Robot Nursery in the Build tab first.": ["Baue zuerst den Roboter-Kindergarten im Bauen-Tab.", "Construye primero la Guardería de robots en la pestaña Construir.", "Construis d'abord la Nurserie à robots dans l'onglet Construire.", "先に建設タブでロボット保育所を建てよう。", "Construa primeiro o Berçário de robôs na aba Construir.", "先在建造页签建好机器人育儿所。"],
"New at the workbench, Build tab: Signal Jammer. It scrambles the Ledger's drones near the base.": ["Neu an der Werkbank, Bauen-Tab: Störsender. Er bringt die Drohnen des Ledgers nahe der Basis durcheinander.", "Nuevo en el banco, pestaña Construir: Inhibidor de señal. Confunde a los drones del Ledger cerca de la base.", "Nouveau à l'établi, onglet Construire : Brouilleur. Il perturbe les drones du Ledger près de la base.", "作業台の建設タブに新項目：信号妨害装置。拠点近くのレジャーのドローンを混乱させます。", "Novo na bancada, aba Construir: Bloqueador de sinal. Confunde os drones do Ledger perto da base.", "工作台建造页签新增：信号干扰器。它会扰乱基地附近的账本无人机。"],
"The hub can grow now. Rebuild it from the Upgrades tab at the workbench.": ["Der Hub kann jetzt wachsen. Bau ihn im Upgrades-Tab der Werkbank aus.", "La base ya puede crecer. Reconstrúyela desde la pestaña Mejoras del banco.", "La base peut grandir. Reconstruis-la depuis l'onglet Améliorations de l'établi.", "ハブを大きくできます。作業台のアップグレードタブから改築しよう。", "A base pode crescer agora. Reconstrua pela aba Melhorias da bancada.", "基地现在可以扩建了。在工作台的升级页签里改建。"],
"Opens at hub level %d (now %d). Upgrade the hub in the Upgrades tab.": ["Öffnet bei Hub-Stufe %d (jetzt %d). Baue den Hub im Upgrades-Tab aus.", "Se abre con la base en nivel %d (ahora %d). Mejora la base en la pestaña Mejoras.", "S'ouvre au niveau %d de la base (actuellement %d). Améliore la base dans l'onglet Améliorations.", "ハブ レベル%dで解放（現在%d）。アップグレードタブでハブを強化しよう。", "Abre com a base no nível %d (agora %d). Melhore a base na aba Melhorias.", "基地%d级时开放（当前%d级）。在升级页签升级基地。"],
"Trash bin, level %d of %d": ["Mülltonne, Stufe %d von %d", "Contenedor, nivel %d de %d", "Poubelle, niveau %d sur %d", "ゴミ箱 レベル%d / %d", "Lixeira, nível %d de %d", "垃圾桶，%d / %d级"],
"Tier %d of %d": ["Stufe %d von %d", "Nivel %d de %d", "Niveau %d sur %d", "ティア %d / %d", "Nível %d de %d", "等级 %d / %d"],
"%d of %d built": ["%d von %d gebaut", "%d de %d construidos", "%d sur %d construits", "%d / %d 建設済み", "%d de %d construídos", "已建 %d / %d"],
"Museum": ["Museum", "Museo", "Musée", "博物館", "Museu", "博物馆"],
"Lv %d  ·  %s%s (max)": ["St. %d  ·  %s%s (max.)", "Nv %d  ·  %s%s (máx.)", "Niv %d  ·  %s%s (max)", "Lv %d  ·  %s%s（最大）", "Nv %d  ·  %s%s (máx.)", "%d级  ·  %s%s（满级）"],
"+  %s cubes": ["+  %s Würfel", "+  %s cubos", "+  %s cubes", "+  %s キューブ", "+  %s cubos", "+  %s 方块"],
"Build the %s first (Build tab)": ["Baue zuerst: %s (Bauen-Tab)", "Construye primero: %s (pestaña Construir)", "Construis d'abord : %s (onglet Construire)", "先に%sを建てよう（建設タブ）", "Construa primeiro: %s (aba Construir)", "先建造%s（建造页签）"],
"Upgrades": ["Upgrades", "Mejoras", "Améliorations", "アップグレード", "Melhorias", "升级"],
"Base": ["Basis", "Base", "Base", "拠点", "Base", "基地"],
"Machines": ["Maschinen", "Máquinas", "Machines", "機械", "Máquinas", "机器"],
"Rocket": ["Rakete", "Cohete", "Fusée", "ロケット", "Foguete", "火箭"],
"Lumi": ["Lumi", "Lumi", "Lumi", "Lumi", "Lumi", "Lumi"],
"Nothing new to build right now. New buildings unlock as you play.": ["Gerade gibt es nichts Neues zu bauen. Neue Gebäude schaltest du beim Spielen frei.", "Ahora no hay nada nuevo que construir. Desbloquearás edificios nuevos jugando.", "Rien de nouveau à construire pour l'instant. De nouveaux bâtiments se débloquent en jouant.", "今は新しく建てるものはありません。遊ぶうちに新しい建物が解放されます。", "Nada novo para construir agora. Novos prédios são desbloqueados jogando.", "目前没有新的可建造项目。新建筑会在游戏中解锁。"],
"Built:  %s": ["Gebaut:  %s", "Construido:  %s", "Construit :  %s", "建設済み：  %s", "Construído:  %s", "已建成：  %s"],
"Add one": ["Eins dazu", "Añadir uno", "En ajouter un", "1つ追加", "Adicionar um", "再加一个"],
"%d of %d": ["%d von %d", "%d de %d", "%d sur %d", "%d / %d", "%d de %d", "%d / %d"],
"Basics": ["Grundlagen", "Básico", "Essentiel", "基本", "Básico", "基础"],
"Keepsakes": ["Andenken", "Recuerdos", "Souvenirs", "記念品", "Lembranças", "纪念品"],
"Quit": ["Beenden", "Salir", "Quitter", "終了", "Sair", "退出"],
"More settings  (sound, graphics, controls, accessibility)": ["Mehr Einstellungen  (Ton, Grafik, Steuerung, Barrierefreiheit)", "Más ajustes  (sonido, gráficos, controles, accesibilidad)", "Plus de réglages  (son, graphismes, commandes, accessibilité)", "その他の設定  （サウンド、グラフィック、操作、アクセシビリティ）", "Mais configurações  (som, gráficos, controles, acessibilidade)", "更多设置  （声音、画面、操作、辅助功能）"],
"Everything else": ["Alles andere", "Todo lo demás", "Tout le reste", "その他すべて", "Todo o resto", "其他全部"],
"need %s": ["fehlt %s", "faltan %s", "manque %s", "あと%s", "faltam %s", "还差%s"],
"need %s · ~%s": ["fehlt %s · ~%s", "faltan %s · ~%s", "manque %s · ~%s", "あと%s · 約%s", "faltam %s · ~%s", "还差%s · 约%s"],
"Need %s more cubes": ["Es fehlen %s Würfel", "Faltan %s cubos", "Il manque %s cubes", "キューブがあと%s必要", "Faltam %s cubos", "还差%s个方块"],
"Fleet upgrades": ["Flotten-Upgrades", "Mejoras de flota", "Améliorations de flotte", "艦隊アップグレード", "Melhorias da frota", "车队升级"],
"Max": ["Max", "Máx.", "Max", "最大", "Máx.", "最大"],
"Not enough parts": ["Nicht genug Teile", "No hay suficientes piezas", "Pas assez de pièces", "パーツが足りません", "Peças insuficientes", "零件不足"],
"%s (robot style)": ["%s (Roboter-Stil)", "%s (estilo de robot)", "%s (style de robot)", "%s（ロボットスタイル）", "%s (estilo de robô)", "%s（机器人外观）"],
"Requests reward: %s. Paint your fleet with it in the Locker.": ["Auftragsbelohnung: %s. Lackiere damit deine Flotte im Spind.", "Recompensa de encargos: %s. Pinta tu flota con ella en la Taquilla.", "Récompense de commandes : %s. Peins ta flotte avec dans le Casier.", "依頼の報酬：%s。ロッカーで艦隊を塗装できます。", "Recompensa de pedidos: %s. Pinte sua frota com ela no Armário.", "委托奖励：%s。在储物柜里给车队涂装。"],
"Requests reward: %s. Fit it in the Locker.": ["Auftragsbelohnung: %s. Bau es im Spind an.", "Recompensa de encargos: %s. Pónsela en la Taquilla.", "Récompense de commandes : %s. Installe-la dans le Casier.", "依頼の報酬：%s。ロッカーで取り付けよう。", "Recompensa de pedidos: %s. Instale no Armário.", "委托奖励：%s。去储物柜装上。"],
"Not unlocked yet": ["Noch nicht freigeschaltet", "Aún no desbloqueado", "Pas encore débloqué", "まだ解放されていません", "Ainda não desbloqueado", "尚未解锁"],
"Unlock · %s": ["Freischalten · %s", "Desbloquear · %s", "Débloquer · %s", "解放 · %s", "Desbloquear · %s", "解锁 · %s"],
"Can't be bought": ["Nicht käuflich", "No se puede comprar", "Ne s'achète pas", "購入できません", "Não pode ser comprado", "无法购买"],
"Your first bot came with treads and a bobble plant. Style it in the Locker once the hub reaches level %d.": ["Dein erster Bot kam mit Ketten und einer Wackelpflanze. Gestalte ihn im Spind, sobald der Hub Stufe %d erreicht.", "Tu primer bot vino con orugas y una planta saltarina. Dale estilo en la Taquilla cuando la base llegue al nivel %d.", "Ton premier robot est arrivé avec des chenilles et une plante à ressort. Personnalise-le dans le Casier quand la base atteint le niveau %d.", "最初のボットにはキャタピラとゆらゆら植物が付いてきた。ハブがレベル%dになったらロッカーで飾ろう。", "Seu primeiro robô veio com esteiras e uma plantinha de mola. Personalize-o no Armário quando a base chegar ao nível %d.", "你的第一台机器人附带履带和一株弹簧小草。基地达到%d级后可在储物柜里装扮它。"],
"%s spotted a %s: %s.": ["%s hat ein(e) %s entdeckt: %s.", "%s encontró: %s, %s.", "%s a repéré : %s, %s.", "%sが%sを見つけた：%s。", "%s encontrou: %s, %s.", "%s发现了%s：%s。"],
"Unlocked  ·  press to fit": ["Freigeschaltet  ·  drücken zum Anbauen", "Desbloqueado  ·  pulsa para equipar", "Débloqué  ·  appuie pour installer", "解放済み  ·  押して装着", "Desbloqueado  ·  pressione para instalar", "已解锁  ·  按下装上"],
"  ·  press to unlock + fit": ["  ·  drücken: freischalten + anbauen", "  ·  pulsa para desbloquear y equipar", "  ·  appuie pour débloquer et installer", "  ·  押して解放＋装着", "  ·  pressione para desbloquear e instalar", "  ·  按下解锁并装上"],
"%d styles unlocked   ·   Parts %s": ["%d Stile freigeschaltet   ·   Teile %s", "%d estilos desbloqueados   ·   Piezas %s", "%d styles débloqués   ·   Pièces %s", "スタイル%d個解放   ·   パーツ %s", "%d estilos desbloqueados   ·   Peças %s", "已解锁%d种外观   ·   零件 %s"],
"ready": ["bereit", "listo", "prêt", "準備OK", "pronto", "就绪"],
"Live now:  %s  ·  %s  ·  %s left": ["Jetzt live:  %s  ·  %s  ·  noch %s", "En directo:  %s  ·  %s  ·  quedan %s", "En cours :  %s  ·  %s  ·  encore %s", "開催中：  %s  ·  %s  ·  残り%s", "Agora:  %s  ·  %s  ·  faltam %s", "进行中：  %s  ·  %s  ·  剩余%s"],
"Every reward unlocked. Each %d more requests pay a Vintage part's worth of parts.": ["Alle Belohnungen freigeschaltet. Alle %d weiteren Aufträge gibt es Teile im Wert eines Vintage-Teils.", "Todas las recompensas desbloqueadas. Cada %d encargos más pagan piezas por valor de una pieza Vintage.", "Toutes les récompenses sont débloquées. Tous les %d commandes de plus rapportent la valeur d'une pièce Vintage.", "報酬はすべて解放済み。依頼を%d件こなすごとにヴィンテージ部品1個分のパーツがもらえます。", "Todas as recompensas desbloqueadas. A cada %d pedidos, peças no valor de uma peça Vintage.", "所有奖励已解锁。每再完成%d个委托，可获得一个古董零件价值的零件。"],
"A new request is on its way": ["Ein neuer Auftrag ist unterwegs", "Un nuevo encargo está en camino", "Une nouvelle commande arrive", "新しい依頼が届きます", "Um novo pedido está a caminho", "新委托即将到来"],
"Claim": ["Abholen", "Reclamar", "Récupérer", "受け取る", "Resgatar", "领取"],
"What you get": ["Das bekommst du", "Lo que obtienes", "Ce que tu obtiens", "得られるもの", "O que você ganha", "你将获得"],
"Upgrade": ["Ausbauen", "Mejorar", "Améliorer", "アップグレード", "Melhorar", "升级"],
"Bales sell for +%d%% (now +%d%%)": ["Ballen bringen +%d%% (jetzt +%d%%)", "Las balas se venden por +%d%% (ahora +%d%%)", "Les balles se vendent +%d%% (actuellement +%d%%)", "ベールの売値+%d%%（現在+%d%%）", "Fardos vendem por +%d%% (agora +%d%%)", "草捆售价+%d%%（当前+%d%%）"],
"+%d robot spots in every crew": ["+%d Roboterplätze in jeder Crew", "+%d plazas de robot en cada equipo", "+%d places de robot dans chaque équipe", "各クルーのロボット枠+%d", "+%d vagas de robô em cada equipe", "每个小队+%d个机器人位"],
"Air Scrubbers: clear the dusty sky": ["Luftwäscher: klären den staubigen Himmel", "Depuradores de aire: limpian el cielo polvoriento", "Épurateurs d'air : dégagent le ciel poussiéreux", "空気清浄機：ほこりっぽい空を澄ませる", "Purificadores de ar: limpam o céu empoeirado", "空气净化器：清除漫天尘埃"],
"Unlocks the %s": ["Schaltet %s frei", "Desbloquea: %s", "Débloque : %s", "%sを解放", "Desbloqueia: %s", "解锁%s"],
"Opens the Locker: style Lumi and your robots": ["Öffnet den Spind: gestalte Lumi und deine Roboter", "Abre la Taquilla: dale estilo a Lumi y a tus robots", "Ouvre le Casier : personnalise Lumi et tes robots", "ロッカーが開く：Lumiとロボットを着せ替え", "Abre o Armário: personalize Lumi e seus robôs", "开启储物柜：装扮Lumi和你的机器人"],
"A launch pad: rockets to the next district": ["Eine Startrampe: Raketen ins nächste Viertel", "Una plataforma de lanzamiento: cohetes al siguiente distrito", "Un pas de tir : des fusées vers le quartier suivant", "発射台：次の地区へロケットで", "Uma plataforma de lançamento: foguetes para o próximo distrito", "发射台：乘火箭前往下一个街区"],
"Now: level %d, %s. Bales sell for +%d%%.": ["Jetzt: Stufe %d, %s. Ballen bringen +%d%%.", "Ahora: nivel %d, %s. Las balas se venden por +%d%%.", "Actuellement : niveau %d, %s. Les balles se vendent +%d%%.", "現在：レベル%d、%s。ベールの売値+%d%%。", "Agora: nível %d, %s. Fardos vendem por +%d%%.", "当前：%d级，%s。草捆售价+%d%%。"],
"Hub level %d  ·  fully built": ["Hub-Stufe %d  ·  fertig ausgebaut", "Base nivel %d  ·  completa", "Base niveau %d  ·  terminée", "ハブ レベル%d  ·  完成", "Base nível %d  ·  completa", "基地%d级  ·  已建满"],
"Every hub level is built.": ["Alle Hub-Stufen sind gebaut.", "Todos los niveles de la base están construidos.", "Tous les niveaux de la base sont construits.", "ハブはすべて完成しました。", "Todos os níveis da base estão construídos.", "基地所有等级均已建成。"],
"Fully built": ["Fertig ausgebaut", "Completa", "Terminée", "完成", "Completa", "已建满"],
"Next: hub level %d": ["Als Nächstes: Hub-Stufe %d", "Siguiente: base nivel %d", "Suivant : base niveau %d", "次：ハブ レベル%d", "Próximo: base nível %d", "下一步：基地%d级"],
"Upgrade to level %d": ["Auf Stufe %d ausbauen", "Mejorar a nivel %d", "Passer au niveau %d", "レベル%dにアップグレード", "Melhorar para nível %d", "升到%d级"],
"Not enough yet": ["Noch nicht genug", "Aún no alcanza", "Pas encore assez", "まだ足りません", "Ainda não é suficiente", "还不够"],
"Opens at hub level %d.": ["Öffnet bei Hub-Stufe %d.", "Se abre con la base en nivel %d.", "S'ouvre au niveau %d de la base.", "ハブ レベル%dで解放。", "Abre com a base no nível %d.", "基地%d级时开放。"],
"All built.": ["Alle gebaut.", "Todos construidos.", "Tous construits.", "すべて建設済み。", "Todos construídos.", "已全部建成。"],
"All built": ["Alle gebaut", "Todos construidos", "Tous construits", "すべて建設済み", "Todos construídos", "已全部建成"],
"Editing": ["Bearbeiten", "Editando", "En édition", "編集中", "Editando", "正在编辑"],
"Fleet paint": ["Flottenlack", "Pintura de flota", "Peinture de flotte", "艦隊の塗装", "Pintura da frota", "车队涂装"],
"The Locker": ["Der Spind", "La Taquilla", "Le Casier", "ロッカー", "O Armário", "储物柜"],
"Style Lumi and every robot: colours, eyes, head pieces, toppers, fleet paint. New pieces unlock as you play.": ["Gestalte Lumi und jeden Roboter: Farben, Augen, Kopfteile, Aufsätze, Flottenlack. Neue Teile schaltest du beim Spielen frei.", "Dale estilo a Lumi y a cada robot: colores, ojos, piezas de cabeza, adornos, pintura de flota. Desbloqueas piezas nuevas jugando.", "Personnalise Lumi et chaque robot : couleurs, yeux, coiffes, accessoires, peinture de flotte. De nouvelles pièces se débloquent en jouant.", "Lumiとすべてのロボットを着せ替え：色、目、頭パーツ、飾り、艦隊の塗装。新しいパーツは遊ぶうちに解放されます。", "Personalize Lumi e cada robô: cores, olhos, peças de cabeça, enfeites, pintura da frota. Novas peças são desbloqueadas jogando.", "装扮Lumi和每台机器人：颜色、眼睛、头饰、顶饰、车队涂装。新部件会在游戏中逐步解锁。"],
"Opens at hub level %d (now %d). Upgrade the hub in the Hub tab.": ["Öffnet bei Hub-Stufe %d (jetzt %d). Baue den Hub im Hub-Tab aus.", "Se abre con la base en nivel %d (ahora %d). Mejora la base en la pestaña Base.", "S'ouvre au niveau %d de la base (actuellement %d). Améliore la base dans l'onglet Base.", "ハブ レベル%dで解放（現在%d）。ハブタブでアップグレードしよう。", "Abre com a base no nível %d (agora %d). Melhore a base na aba Base.", "基地%d级时开放（当前%d级）。在基地页签升级基地。"],
"You": ["Du", "Tú", "Toi", "あなた", "Você", "你"],
"Crew": ["Crew", "Equipo", "Équipe", "クルー", "Equipe", "小队"],
"Tier": ["Stufe", "Nivel", "Niveau", "ティア", "Nível", "等级"],
"Build": ["Bauen", "Construir", "Construire", "作る", "Construir", "建造"],
"Open Research": ["Forschung öffnen", "Abrir Investigación", "Ouvrir la Recherche", "研究を開く", "Abrir Pesquisa", "打开研究"],
"Unlock with research: %s": ["Freischalten durch Forschung: %s", "Se desbloquea investigando: %s", "Se débloque par la recherche : %s", "研究で解放：%s", "Desbloqueie pesquisando: %s", "通过研究解锁：%s"],
"%d built  ·  full: more spots with hub levels": ["%d gebaut  ·  voll: mehr Plätze mit Hub-Stufen", "%d construidos  ·  lleno: más plazas con niveles de base", "%d construits  ·  complet : plus de places avec les niveaux de base", "%d台  ·  満員：ハブレベルで枠が増えます", "%d construídos  ·  cheio: mais vagas com níveis da base", "已建%d台  ·  已满：基地升级可增加名额"],
"%d built  ·  %d free": ["%d gebaut  ·  %d frei", "%d construidos  ·  %d libres", "%d construits  ·  %d libres", "%d台  ·  空き%d", "%d construídos  ·  %d livres", "已建%d台  ·  空位%d"],
"Water Tanks %d / %d  ·  place them from the Command view": ["Wassertanks %d / %d  ·  in der Kommandoansicht aufstellen", "Tanques de agua %d / %d  ·  colócalos desde la vista de mando", "Réservoirs d'eau %d / %d  ·  à placer depuis la vue Commande", "給水タンク %d / %d  ·  コマンドビューで設置", "Tanques de água %d / %d  ·  coloque pela visão de comando", "储水罐 %d / %d  ·  在指挥视图中放置"],
"Build first": ["Ersten bauen", "Construir el primero", "Construire le premier", "最初の1台を作る", "Construir o primeiro", "建造第一台"],
"top tier": ["höchste Stufe", "nivel máximo", "niveau max", "最高ティア", "nível máximo", "最高等级"],
"next: x%s work speed": ["nächste: x%s Arbeitstempo", "siguiente: x%s velocidad de trabajo", "suivant : vitesse de travail x%s", "次：作業速度x%s", "próximo: x%s velocidade de trabalho", "下一级：工作速度x%s"],
"Locker": ["Spind", "Taquilla", "Casier", "ロッカー", "Armário", "储物柜"],
"WORKBENCH": ["WERKBANK", "BANCO DE TRABAJO", "ÉTABLI", "作業台", "BANCADA", "工作台"],
"Not open yet. Keep playing.": ["Noch nicht offen. Spiel weiter.", "Aún no está abierto. Sigue jugando.", "Pas encore ouvert. Continue à jouer.", "まだ開いていません。プレイを続けよう。", "Ainda não abriu. Continue jogando.", "尚未开放。继续游戏吧。"],
"Style a robot with all five custom parts in the Locker.": ["Gestalte im Spind einen Roboter mit allen fünf Spezialteilen.", "Dale estilo a un robot con las cinco piezas personalizadas en la Taquilla.", "Personnalise un robot avec les cinq pièces dans le Casier.", "ロッカーでロボットに5つのカスタムパーツをすべて付けよう。", "Personalize um robô com as cinco peças no Armário.", "在储物柜里给一台机器人装满五个自定义部件。"],
"Style a robot in the Locker": ["Gestalte einen Roboter im Spind", "Dale estilo a un robot en la Taquilla", "Personnalise un robot au Casier", "ロッカーでロボットを飾る", "Personalize um robô no Armário", "在储物柜装扮一台机器人"],
"With enough parts, the workbench can put a helper together. Bots tab, one button.": ["Mit genug Teilen baut die Werkbank einen Helfer zusammen. Bots-Tab, ein Knopf.", "Con suficientes piezas, el banco de trabajo puede montar un ayudante. Pestaña Bots, un botón.", "Avec assez de pièces, l'établi peut assembler un assistant. Onglet Bots, un bouton.", "パーツが足りれば作業台で助っ人を組み立てられる。ボットタブ、ボタンひとつ。", "Com peças suficientes, a bancada monta um ajudante. Aba Bots, um botão.", "零件够了，工作台就能组装一个帮手。机器人页签，一个按钮。"],
"Comes with your first robot": ["Kommt mit deinem ersten Roboter", "Viene con tu primer robot", "Livré avec ton premier robot", "最初のロボットに付属", "Vem com seu primeiro robô", "随第一台机器人附赠"],
"Rubber tracks.": ["Gummiketten.", "Orugas de goma.", "Chenilles en caoutchouc.", "ゴムのキャタピラ。", "Esteiras de borracha.", "橡胶履带。"],
"Four ducted fans.": ["Vier Mantelpropeller.", "Cuatro ventiladores carenados.", "Quatre hélices carénées.", "4基のダクトファン。", "Quatro ventoinhas carenadas.", "四个涵道风扇。"],
"Four careful legs.": ["Vier vorsichtige Beine.", "Cuatro patas cuidadosas.", "Quatre pattes prudentes.", "慎重な4本脚。", "Quatro pernas cuidadosas.", "四条小心翼翼的腿。"],
"A big, wide scoop.": ["Eine große, breite Schaufel.", "Una pala grande y ancha.", "Une grande pelle large.", "大きくて幅広いスコップ。", "Uma pá grande e larga.", "一把又大又宽的铲斗。"],
"Extra-long forks.": ["Extralange Gabeln.", "Horquillas extralargas.", "Fourches extra-longues.", "特長のフォーク。", "Garfos extralongos.", "超长货叉。"],
"Winch and hook.": ["Seilwinde und Haken.", "Cabrestante y gancho.", "Treuil et crochet.", "ウインチとフック。", "Guincho e gancho.", "绞盘和吊钩。"],
"An auger nose.": ["Eine Bohrernase.", "Una nariz de barrena.", "Un nez en tarière.", "オーガーの鼻先。", "Um nariz de broca.", "螺旋钻鼻。"],
"A fan nozzle.": ["Eine Fächerdüse.", "Una boquilla de abanico.", "Une buse en éventail.", "扇形ノズル。", "Um bico em leque.", "扇形喷嘴。"],
"A strong, straight jet nozzle.": ["Eine kräftige, gerade Strahldüse.", "Una boquilla de chorro fuerte y recto.", "Une buse à jet droit et puissant.", "まっすぐ強い噴射ノズル。", "Um bico de jato forte e reto.", "强劲笔直的喷射嘴。"],
"Blinkers for robots.": ["Scheuklappen für Roboter.", "Anteojeras para robots.", "Des œillères pour robots.", "ロボット用の目隠し。", "Antolhos para robôs.", "机器人用的眼罩。"],
"A huge lens on a stalk.": ["Eine riesige Linse auf einem Stiel.", "Una lente enorme sobre un tallo.", "Une énorme lentille sur une tige.", "茎の先に巨大なレンズ。", "Uma lente enorme numa haste.", "杆子上的一个巨大镜头。"],
"Thick side plates and a rear rack.": ["Dicke Seitenplatten und ein Heckträger.", "Placas laterales gruesas y una parrilla trasera.", "Épaisses plaques latérales et un porte-bagages arrière.", "分厚いサイドプレートと後部ラック。", "Placas laterais grossas e um bagageiro traseiro.", "厚实的侧板和后置货架。"],
"Smooth covers, neat seams, no grit.": ["Glatte Abdeckungen, saubere Nähte, kein Dreck.", "Cubiertas lisas, costuras limpias, sin arenilla.", "Capots lisses, joints nets, pas de poussière.", "なめらかなカバー、きれいな継ぎ目、砂ぼこりなし。", "Capas lisas, emendas limpas, sem sujeira.", "光滑外壳，接缝整齐，一尘不染。"],
"Sees over the plants. Mostly.": ["Sieht über die Pflanzen. Meistens.", "Ve por encima de las plantas. Casi siempre.", "Voit par-dessus les plantes. Presque toujours.", "植物の上まで見える。だいたいは。", "Enxerga por cima das plantas. Quase sempre.", "能越过植物看清楚。大多数时候。"],
"Glass dome with a little speaker.": ["Glaskuppel mit kleinem Lautsprecher.", "Cúpula de cristal con un altavoz pequeño.", "Dôme de verre avec un petit haut-parleur.", "小さなスピーカー付きのガラスドーム。", "Cúpula de vidro com um alto-falante pequeno.", "带小扬声器的玻璃罩。"],
"A cushion of air and a soft glow underneath.": ["Ein Luftkissen und ein sanftes Leuchten darunter.", "Un colchón de aire y un brillo suave debajo.", "Un coussin d'air et une douce lueur dessous.", "空気のクッションと、下にやわらかな光。", "Um colchão de ar e um brilho suave por baixo.", "一层气垫，底下透着柔光。"],
"A sieve that shakes out the dirt.": ["Ein Sieb, das den Dreck ausschüttelt.", "Un tamiz que sacude la tierra.", "Un tamis qui secoue la terre.", "土をふるい落とすふるい。", "Uma peneira que sacode a sujeira.", "能抖掉泥土的筛子。"],
}
PLURALS = {
"%d done": [["%d erledigt", "%d erledigt"], ["%d hecho", "%d hechos"], ["%d terminée", "%d terminées"], ["%d件完了"], ["%d feito", "%d feitos"], ["已完成%d个"]],
"Next unlock in %d request:  %s": [["Nächste Freischaltung in %d Auftrag:  %s", "Nächste Freischaltung in %d Aufträgen:  %s"], ["Próximo desbloqueo en %d encargo:  %s", "Próximo desbloqueo en %d encargos:  %s"], ["Prochain déblocage dans %d commande :  %s", "Prochain déblocage dans %d commandes :  %s"], ["次の解放まで依頼%d件：  %s"], ["Próximo desbloqueio em %d pedido:  %s", "Próximo desbloqueio em %d pedidos:  %s"], ["再完成%d个委托解锁：  %s"]],
}
LANGS = ["de", "es", "fr", "ja", "pt_BR", "zh_CN"]


def esc(t):
	return t.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main():
	total = 0
	for li, lang in enumerate(LANGS):
		p = "locale/%s.po" % lang
		s = open(p, encoding="utf-8").read()
		n = 0
		for k, v in T.items():
			pat = 'msgid "%s"\nmsgstr ""\n' % esc(k)
			if pat in s:
				s = s.replace(pat, 'msgid "%s"\nmsgstr "%s"\n' % (esc(k), esc(v[li])), 1)
				n += 1
		for k, forms in PLURALS.items():
			m = re.search(r'msgid "%s"\nmsgid_plural "[^"]*"\n((?:msgstr\[\d\] ""\n)+)' % re.escape(esc(k)), s)
			if not m:
				continue
			cnt = m.group(1).count("msgstr[")
			f = forms[li]
			rep = "".join('msgstr[%d] "%s"\n' % (i, esc(f[min(i, len(f) - 1)])) for i in range(cnt))
			s = s[:m.start(1)] + rep + s[m.end(1):]
			n += 1
		open(p, "w", encoding="utf-8").write(s)
		print(lang, n)
		total += n
	return total


if __name__ == "__main__":
	main()
