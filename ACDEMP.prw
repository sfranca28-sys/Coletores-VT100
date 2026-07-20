#INCLUDE "TOTVS.CH"
#INCLUDE "APVT100.CH"

#DEFINE ACD_VERSAO      "2.0"
#DEFINE TEMPO_CONSULTA  7000   // ms que a tela de consulta permanece visivel

/*/{Protheus.doc} ACDEMP
Rotina de coletor (Telnet / VT100) para apontamento de Ordem de Producao.

Fluxo:
    ACDEMP     -> prepara o ambiente e controla o laco Login -> Menu
    LoginOpe   -> autentica o operador na tabela SZ1
    MenuOpc    -> menu do operador (1-Apontamento / 2-Consulta)
    ValidaOP   -> le a OP e decide iniciar ou encerrar o apontamento
    ConsultaOP -> mostra o saldo da OP
    IniciaOP   -> registra o inicio do apontamento (Z03)
    ApontaOP   -> registra o fim e gera o apontamento oficial (SH6 / MATA681)

Ao concluir uma operacao, o controle volta para a tela de login.

@type    function
@author  ALWA Solucoes em Tecnologia
@since   04/2025
@version 2.0 (refatoracao)
/*/
User Function ACDEMP()

    Local lLogado := .F.

    // Estado da sessao compartilhado entre as telas
    Private cOrdProd := ""

    // Controle padrao do MSExecAuto
    Private lMsErroAuto    := .F.
    Private lAutoErrNoFile := .T.
    Private lMsHelpAuto    := .T.
    Private aLog           := {}

    PrepararAmbiente()
    cOrdProd := Space(TamSx3("H6_OP")[1])
    
    VTSetSize(32, 80)

    While .T.
        lLogado := LoginOpe()

        // ESC na tela de login encerra a sessao do coletor
        If !lLogado
            Exit
        EndIf

        // Executa uma operacao e retorna para a tela de login
        MenuOpc()
    EndDo

    VTClear()
    VTAlert("SESSAO ENCERRADA", "ACDEMP", .T., 1500, 1)

Return .T.

// ---------------------------------------------------------------------------
// Prepara o ambiente RPC caso o Job ainda nao tenha carregado.
// OBS: empresa/filial estao fixas ("01"/"01"). O ideal e parametrizar via
// configuracao do Job no appserver.ini.
// ---------------------------------------------------------------------------
Static Function PrepararAmbiente()

    If Select("SX2") == 0
        RpcClearEnv()
        RpcSetType(3)
        RpcSetEnv("01", "04")
    EndIf

Return

// ---------------------------------------------------------------------------
// Tela de login. Repete ate autenticar ou ate o operador pressionar ESC.
// ---------------------------------------------------------------------------
Static Function LoginOpe()

    Local lRet     := .F.
    Local cOperInf := ""
    Local aRpo     := GetApoInfo("ACDEMP.prw")

    While .T.
        VTClear()
        VTClearBuffer()

        cOperInf := Space(6)

        @ 00,00 VTSay "      EMPLAS        "
        @ 01,00 VTSay "--------------------"
        @ 03,00 VTSay "v" + ACD_VERSAO + " " + Right(DtoS(aRpo[4]), 6)
        @ 05,00 VTSay "LOGIN " VTGet cOperInf Picture "@!"
        VTRead

        // ESC encerra o login (e a aplicacao)
        If VTLastKey() == 27
            lRet := .F.
            Exit
        EndIf

        If ValidOper(AllTrim(Upper(cOperInf)))
            lRet := .T.
            Exit
        EndIf
    EndDo

Return lRet

// ---------------------------------------------------------------------------
// Valida o operador do login. Ao autenticar, ajusta a filial da sessao,
// abre os arquivos da filial e posiciona o SZ1 no operador logado.
// ---------------------------------------------------------------------------
Static Function ValidOper(cCodOper)

    Local lRet     := .F.
    Local cNumEmp  := ""

    If Empty(cCodOper)
        Return .F.
    EndIf

    DbSelectArea("SZ1")
    SZ1->(DbSetOrder(1))

    If SZ1->(DbSeek(cCodOper))
        cFilAnt := SZ1->Z1_FILIAL
        cNumEmp := cEmpAnt + cFilAnt
        OpenFile(cNumEmp)
        // Reposiciona no operador logado apos o OpenFile
        SZ1->(DbSeek(cCodOper))
        lRet := .T.
    Else
        VTAlert("OPERADOR INVALIDO!", "AVISO", .T., 2000, 1)
    EndIf

Return lRet

// ---------------------------------------------------------------------------
// Verifica se um operador existe SEM alterar filial/arquivos nem a posicao
// atual do SZ1. Usado para validar o "operador 2" (opcional).
// ---------------------------------------------------------------------------
Static Function ExisteOper(cCodOper)

    Local lRet    := .T.
    Local nRecSZ1 := SZ1->(Recno())

    // Operador 2 e opcional: em branco e valido
    If Empty(cCodOper)
        Return .T.
    EndIf

    SZ1->(DbSetOrder(1))
    lRet := SZ1->(DbSeek(PadR(AllTrim(Upper(cCodOper)), TamSx3("Z1_COD")[1])))

    If !lRet
        VTAlert("OPERADOR 2 INVALIDO", "AVISO", .T., 2000, 1)
    EndIf

    // Restaura a posicao do operador logado
    SZ1->(DbGoto(nRecSZ1))

Return lRet

// ---------------------------------------------------------------------------
// Menu do operador. Executa uma opcao e retorna (voltando para o login).
// ESC = volta para o login. Opcao invalida = reexibe o menu.
// ---------------------------------------------------------------------------
Static Function MenuOpc()

    Local cOpcao := "1"

    While .T.
        VTClear()
        VTClearBuffer()

        cOpcao := "1"

        @ 00,00 VTSay SZ1->Z1_FILIAL + " - " + SZ1->Z1_COD
        @ 01,00 VTSay Left(SZ1->Z1_NOME, 20)
        @ 03,02 VTSay "1. APONTAMENTO"
        @ 04,02 VTSay "2. CONSULTA"
        @ 06,00 VTSay "OPCAO..: " VTGet cOpcao Picture "9"
        VTRead

        If VTLastKey() == 27  // volta ao login
            Exit
        EndIf

        Do Case
        Case cOpcao == "1"
            ValidaOP()
            Exit
        Case cOpcao == "2"
            ConsultaOP()
            Exit
        Otherwise
            VTAlert("OPCAO INVALIDA!", "AVISO", .T., 2000, 1)
        EndCase
    EndDo

Return

// ---------------------------------------------------------------------------
// Le a OP, valida na SC2 e decide se inicia ou encerra o apontamento,
// conforme exista (ou nao) um Z03 aberto (sem data de apontamento).
// ---------------------------------------------------------------------------
Static Function ValidaOP()

    Local cChaveOP   := ""
    Local cQuery     := ""
    Local lTemAberto := .F.
    Local nRecZ03    := 0

    While .T.
        VTClear()
        VTClearBuffer()

        cOrdProd := Space(TamSx3("H6_OP")[1])

        @ 00,00 VTSay SZ1->Z1_FILIAL + " - " + SZ1->Z1_COD
        @ 01,00 VTSay Left(SZ1->Z1_NOME, 20)
        @ 03,00 VTSay "LEIA OU DIGITE A OP:"
        @ 04,00 VTGet cOrdProd Picture "@!"
        VTRead

        If VTLastKey() == 27  // volta ao login
            Exit
        EndIf

        DbSelectArea("SC2")
        SC2->(DbSetOrder(1))

        If !SC2->(DbSeek(xFilial("SC2") + cOrdProd))
            VTAlert("OP NAO LOCALIZADA!", "ERRO", .T., 2000, 1)
            Loop
        EndIf

        If SC2->C2_QUANT <= SC2->C2_QUJE
            VTAlert("ORDEM DE PRODUCAO JA ENCERRADA.", "AVISO", .T., 2000, 1)
            Loop
        EndIf

        cChaveOP := SC2->C2_NUM + SC2->C2_ITEM + SC2->C2_SEQUEN
        cOrdProd := cChaveOP

        // Existe apontamento iniciado e ainda nao encerrado?
        cQuery := " SELECT Z03.R_E_C_N_O_ AS RECZ03 "
        cQuery += " FROM " + RetSqlName("Z03") + " Z03 "
        cQuery += " WHERE Z03.D_E_L_E_T_ = ' ' "
        cQuery += "   AND Z03.Z03_FILIAL = '" + xFilial("Z03") + "' "
        cQuery += "   AND Z03.Z03_OP     = '" + cChaveOP + "' "
        cQuery += "   AND Z03.Z03_PRODUT = '" + SC2->C2_PRODUTO + "' "
        cQuery += "   AND Z03.Z03_DTAPON = ' ' "

        cQuery := ChangeQuery(cQuery)
        MpSysOpenQuery(cQuery, "TMPZ03")

        lTemAberto := !TMPZ03->(Eof())
        If lTemAberto
            nRecZ03 := TMPZ03->RECZ03
        EndIf

        TMPZ03->(DbCloseArea())

        If lTemAberto
            DbSelectArea("Z03")
            Z03->(DbGoto(nRecZ03))
            ApontaOP()   // encerra
        Else
            IniciaOP(cChaveOP)   // inicia
        EndIf

        Exit  // apos processar, retorna ao menu -> login
    EndDo

Return

// ---------------------------------------------------------------------------
// Consulta o saldo (quantidade original / apontada / faltante) da OP.
// ---------------------------------------------------------------------------
Static Function ConsultaOP()

    While .T.
        VTClear()
        VTClearBuffer()

        cOrdProd := Space(TamSx3("H6_OP")[1])

        @ 00,00 VTSay SZ1->Z1_FILIAL + " - " + SZ1->Z1_COD
        @ 01,00 VTSay Left(SZ1->Z1_NOME, 20)
        @ 04,00 VTSay "LEIA OU DIGITE A OP:"
        @ 05,00 VTGet cOrdProd Picture "@!"
        @ 07,00 VTSay "  CONSULTA SALDO   "
        VTRead

        If VTLastKey() == 27  // volta ao login
            Exit
        EndIf

        DbSelectArea("SC2")
        SC2->(DbSetOrder(1))

        If !SC2->(DbSeek(xFilial("SC2") + cOrdProd))
            VTAlert("OP NAO LOCALIZADA!", "ERRO", .T., 2000, 1)
            Loop
        EndIf

        VTClear()
        VTClearBuffer()

        @ 00,00 VTSay "  CONSULTA OP  "
        @ 02,00 VTSay "OP:   " + cOrdProd
        @ 04,00 VTSay "QTD ORIGINAL_: " + Transform(SC2->C2_QUANT, "@E 999999")
        @ 06,00 VTSay "QTD APONTADA_: " + Transform(SC2->C2_QUJE, "@E 999999")
        @ 08,00 VTSay "FALTA________: " + Transform(SC2->C2_QUANT - SC2->C2_QUJE, "@E 999999")

        Sleep(TEMPO_CONSULTA)
        Exit  // retorna ao menu -> login
    EndDo

Return

// ---------------------------------------------------------------------------
// Registra o INICIO do apontamento na tabela Z03.
// ---------------------------------------------------------------------------
Static Function IniciaOP(cChaveOP)

    Local cOperacao := Space(TamSx3("G2_OPERAC")[1])
    Local cRecurso  := Space(TamSx3("Z03_RECURS")[1])
    Local cFerramen := Space(TamSx3("G2_FERRAM")[1])
    Local cOper02   := Space(TamSx3("Z1_COD")[1])

    VTClear()
    VTClearBuffer()

    // Sugestao de operacao/ferramenta a partir do roteiro (SG2).
    // O recurso permanece em branco para leitura manual.
    SG2->(DbSetOrder(1))
    If SG2->(DbSeek(xFilial("SG2") + SC2->C2_PRODUTO + SC2->C2_ROTEIRO))
        cOperacao := SG2->G2_OPERAC
        cFerramen := SG2->G2_FERRAM
    EndIf

    @ 00,00 VTSay "  INICIAR PRODUCAO  "
    @ 02,00 VTSay "OP:        " + cChaveOP
    @ 03,00 VTSay "DT INICIO: " + DtoC(Date())
    @ 04,00 VTSay "HR INICIO: " + Left(Time(), 5)
    @ 06,00 VTSay "OPERADOR 2:" VTGet cOper02  Picture "@!" Valid ExisteOper(cOper02)
    @ 07,00 VTSay "RECURSO:   " VTGet cRecurso Picture "@!" Valid ValidRecurs(cRecurso)
    VTRead

    If VTLastKey() == 27  // cancela e volta ao login
        VTAlert("OPERACAO CANCELADA", "AVISO", .T., 2000, 1)
        Return
    EndIf

    SH1->(DbSetOrder(1))
    If !SH1->(DbSeek(xFilial("SH1") + cRecurso))
        VTAlert("RECURSO NAO CADASTRADO", "AVISO", .T., 2000, 1)
        Return
    EndIf

    If RecLock("Z03", .T.)
        Z03->Z03_FILIAL := xFilial("Z03")
        Z03->Z03_OP     := cChaveOP
        Z03->Z03_LOCAL  := SC2->C2_LOCAL
        Z03->Z03_PRODUT := SC2->C2_PRODUTO
        Z03->Z03_OPERAC := cOperacao
        Z03->Z03_ROTEIR := SC2->C2_ROTEIRO
        Z03->Z03_RECURS := cRecurso
        Z03->Z03_FERRAM := cFerramen
        Z03->Z03_DATAIN := Date()
        Z03->Z03_HORAIN := Left(Time(), 5)
        Z03->Z03_OPERAD := SZ1->Z1_COD
        Z03->Z03_OPERA2 := PadR(AllTrim(cOper02), TamSx3("Z03_OPERA2")[1])
        Z03->(MsUnlock())

        VTAlert("OP " + AllTrim(cChaveOP) + " INICIADA", "AVISO", .T., 2000, 1)
    Else
        VTAlert("NAO FOI POSSIVEL BLOQUEAR O REGISTRO", "ERRO", .T., 2000, 1)
    EndIf

Return

// ---------------------------------------------------------------------------
// Registra o FIM do apontamento (Z03) e gera o apontamento oficial (SH6).
// Assume o Z03 ja posicionado no registro aberto.
// ---------------------------------------------------------------------------
Static Function ApontaOP()

    Local nQtdFardos := 0
    Local nLimite    := 0
    Local nUltEtiq   := 0
    Local cQuery     := ""

    // Limite (com 10% de tolerancia) calculado enquanto a SC2 esta posicionada
    nLimite := (SC2->C2_QUANT - SC2->C2_QUJE) * 1.1

    SB1->(DbSetOrder(1))
    SB1->(DbSeek(xFilial("SB1") + Z03->Z03_PRODUT))

    VTClear()
    VTClearBuffer()

    @ 00,00 VTSay " FINALIZAR PRODUCAO "
    @ 02,00 VTSay "OP:     " + Z03->Z03_OP
    @ 03,00 VTSay "RECURSO:" + Z03->Z03_RECURS
    @ 04,00 VTSay "INICIO: " + Right(DtoS(Z03->Z03_DATAIN), 6) + " " + Left(Z03->Z03_HORAIN, 5)
    @ 05,00 VTSay "FIM:    " + Right(DtoS(Date()), 6) + " " + Left(Time(), 5)
    @ 07,00 VTSay "QUANT. FARDOS: " VTGet nQtdFardos Picture "@E 999999" Valid ValidQtd(nQtdFardos, nLimite)
    VTRead

    If VTLastKey() == 27  // cancela e volta ao login
        VTAlert("OPERACAO CANCELADA", "AVISO", .T., 2000, 1)
        Return
    EndIf

    SH1->(DbSetOrder(1))
    If !SH1->(DbSeek(xFilial("SH1") + Z03->Z03_RECURS))
        VTAlert("RECURSO NAO CADASTRADO", "AVISO", .T., 2000, 1)
        Return
    EndIf

    // Ultima etiqueta ja gerada para a OP
    cQuery := " SELECT MAX(Z03_ETIFIN) AS ULTETIQ "
    cQuery += " FROM " + RetSqlName("Z03") + " Z03 "
    cQuery += " WHERE Z03.D_E_L_E_T_ = ' ' "
    cQuery += "   AND Z03.Z03_FILIAL = '" + Z03->Z03_FILIAL + "' "
    cQuery += "   AND Z03.Z03_OP     = '" + Z03->Z03_OP + "' "

    cQuery := ChangeQuery(cQuery)
    MpSysOpenQuery(cQuery, "TMPETI")
    nUltEtiq := IIf(TMPETI->(Eof()) .Or. Empty(TMPETI->ULTETIQ), 0, TMPETI->ULTETIQ)
    TMPETI->(DbCloseArea())

    // Grava dados de encerramento no Z03
    If RecLock("Z03", .F.)
        Z03->Z03_DATAFI := Date()
        Z03->Z03_HORAFI := Left(Time(), 5)
        Z03->Z03_QTDPRO := nQtdFardos * SB1->B1_QTDFARD
        Z03->Z03_QTDPER := 0
        Z03->Z03_DTAPON := Date()
        Z03->Z03_ETIINI := nUltEtiq + 1
        Z03->Z03_ETIFIN := nUltEtiq + nQtdFardos
        Z03->(MsUnlock())
    EndIf

    // Gera o apontamento oficial (SH6) via MATA681
    If GrvApont()
        VTClear()
        VTClearBuffer()
        u_EMACD001(SH6->(Recno()))
    EndIf

Return

// ---------------------------------------------------------------------------
// Valida a quantidade informada contra o limite da OP.
// ---------------------------------------------------------------------------
Static Function ValidQtd(nValor, nLimite)

    Local aTela := VTSave(0, 0, VTMaxRow(), VTMaxCol())
    Local lRet  := .T.

    If nValor < 1
        VTAlert("INFORME A QUANTIDADE PRODUZIDA", "ATENCAO", .T., 2000, 1)
        lRet := .F.
    ElseIf nValor > nLimite
        VTAlert("PRODUCAO ACIMA DO LIMITE DA OP", "ATENCAO", .T., 2000, 1)
        lRet := .F.
    EndIf

    VTRestore(0, 0, VTMaxRow(), VTMaxCol(), aTela)

Return lRet

// ---------------------------------------------------------------------------
// Valida se o recurso informado existe na SH1.
// ---------------------------------------------------------------------------
Static Function ValidRecurs(cRecurso)

    Local lRet := .T.

    SH1->(DbSetOrder(1))
    If !SH1->(DbSeek(xFilial("SH1") + cRecurso))
        VTAlert("RECURSO NAO CADASTRADO", "AVISO", .T., 2000, 1)
        lRet := .F.
    EndIf

Return lRet

// ---------------------------------------------------------------------------
// Executa o MATA681 (apontamento de producao). Em caso de erro, desfaz o
// encerramento gravado no Z03. Retorna .T. quando o apontamento e gerado.
// ---------------------------------------------------------------------------
Static Function GrvApont()

    Local aDados   := {}
    Local cMsgErro := ""
    Local nX       := 0

    lMsErroAuto := .F.

    DbSelectArea("SH6")
    SH6->(DbSetOrder(1))

    aAdd(aDados, {"H6_FILIAL"  , xFilial("SH6")   , Nil})
    aAdd(aDados, {"H6_OP"      , Z03->Z03_OP      , Nil})
    aAdd(aDados, {"H6_PRODUTO" , Z03->Z03_PRODUT  , Nil})
    aAdd(aDados, {"H6_OPERAC"  , Z03->Z03_OPERAC  , Nil})
    aAdd(aDados, {"H6_RECURSO" , Z03->Z03_RECURS  , Nil})
    aAdd(aDados, {"H6_FERRAM"  , Z03->Z03_FERRAM  , Nil})
    aAdd(aDados, {"H6_DTAPONT" , Date()           , Nil})
    aAdd(aDados, {"H6_DATAINI" , Z03->Z03_DATAIN  , Nil})
    aAdd(aDados, {"H6_HORAINI" , Z03->Z03_HORAIN  , Nil})
    aAdd(aDados, {"H6_DATAFIN" , Z03->Z03_DATAFI  , Nil})
    aAdd(aDados, {"H6_HORAFIN" , Z03->Z03_HORAFI  , Nil})
    aAdd(aDados, {"H6_LOCAL"   , Z03->Z03_LOCAL   , Nil})
    aAdd(aDados, {"H6_QTDPROD" , Z03->Z03_QTDPRO  , Nil})
    aAdd(aDados, {"H6_QTDPERD" , Z03->Z03_QTDPER  , Nil})

    aDados := FwVetByDic(aDados, "SH6")

    // Em coletor (VT) nao ha interface grafica: chama o ExecAuto direto.
    VTClear()
    @ 05,00 VTSay "APONTANDO OP " + AllTrim(Z03->Z03_OP)
    @ 07,00 VTSay "AGUARDE..."

    MSExecAuto({|x| Mata681(x)}, aDados, 3)  // 3 = inclusao

    VTClear()
    VTClearBuffer()
    
    If lMsErroAuto
        aLog := GetAutoGRLog()
        For nX := 1 To Len(aLog)
            If nX == 1 .Or. "INVALIDO" $ Upper(aLog[nX])
                cMsgErro += aLog[nX] + CRLF
            EndIf
        Next nX
        VTAlert(cMsgErro, "ERRO NO APONTAMENTO", .T., 3000, 1)

        // Desfaz o encerramento gravado no Z03
        If RecLock("Z03", .F.)
            Z03->Z03_DATAFI := StoD("")
            Z03->Z03_HORAFI := ""
            Z03->Z03_QTDPRO := 0
            Z03->Z03_QTDPER := 0
            Z03->Z03_DTAPON := StoD("")
            Z03->Z03_ETIINI := 0
            Z03->Z03_ETIFIN := 0
            Z03->(MsUnlock())
        EndIf
    Else
        // Vincula o SH6 recem gerado ao Z03 e grava os operadores no SH6
        If RecLock("Z03", .F.)
            Z03->Z03_DTAPON := Date()
            Z03->Z03_RECSH6 := SH6->(Recno())
            Z03->(MsUnlock())
        EndIf

        If RecLock("SH6", .F.)
            SH6->H6_OPERADO := AllTrim(Z03->Z03_OPERAD) + "/" + AllTrim(Z03->Z03_OPERA2)
            SH6->(MsUnlock())
        EndIf

        VTAlert("APONTAMENTO FINALIZADO", "SUCESSO", .T., 2000, 1)
    EndIf

Return !lMsErroAuto
